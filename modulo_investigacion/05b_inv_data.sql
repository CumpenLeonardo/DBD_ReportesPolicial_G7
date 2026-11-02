-- ===================================================================
-- GEO-DENUNCIA | Grupo 07 | Modulo INV (Investigacion, Asignacion y Operativos)
-- 05b_inv_data.sql : parametro N, asignaciones, historial de estados, equipo de apoyo y operativos.
--
-- PRERREQUISITOS (deben existir antes de ejecutar):
--   03_inv_ddl.sql y 04_inv_triggers.sql
--   Andy    : TB_CPL_COMPLAINT con datos (05_cpl_data.sql)
--   Leonardo: TB_STAFF_OFFICER (minimo 3 oficiales), TB_TERR_SECTOR
--   TB_CFG_PARAMETER
--
-- No depende del paquete PKG_INV_MGMT (inserta directo para poder fechar en el pasado).
--
-- Ejecutar con F5 (Run Script) en SQL Developer.
-- ===================================================================

SET SERVEROUTPUT ON;

-- 4.1 Parametro del limite N (si no existe)
MERGE INTO TB_CFG_PARAMETER p
USING (SELECT 'MAX_ACTIVE_CASES' AS param_name FROM dual) s
   ON (p.param_name = s.param_name)
WHEN NOT MATCHED THEN
  INSERT (param_name, param_value, description)
  VALUES ('MAX_ACTIVE_CASES', '15', 'Limite N de casos activos por investigador (RN-08)');

-- 4.3 Asignaciones, historial coherente, equipo de apoyo y operativos
--     Recorre hasta 40 denuncias sin historial y les asigna una de 7 trayectorias validas.
DECLARE
  TYPE t_str  IS TABLE OF VARCHAR2(30);
  TYPE t_cips IS TABLE OF TB_STAFF_OFFICER.officer_cip%TYPE;
  TYPE t_nums IS TABLE OF NUMBER INDEX BY PLS_INTEGER;

  v_cips    t_cips;
  v_n_off   PLS_INTEGER;
  v_now     TIMESTAMP := SYSTIMESTAMP;
  v_i       PLS_INTEGER := 0;
  v_path    t_str;
  v_base    TIMESTAMP;
  v_ts      TIMESTAMP;
  v_ts_inv  TIMESTAMP;
  v_ts_int  TIMESTAMP;
  v_last    VARCHAR2(30);
  v_by_cip  VARCHAR2(15);
  v_det     VARCHAR2(15);
  v_actor   VARCHAR2(15);
  v_closed  BOOLEAN;
  v_op      NUMBER;
  v_hist    t_nums;     -- denuncias que ya pasaron por INTERVENCION (operativos historicos)
  v_dummy   NUMBER;
  v_ts2     TIMESTAMP;
  v_reason  VARCHAR2(300);
  v_prev    VARCHAR2(30);
  v_sup     VARCHAR2(15);

  FUNCTION get_path(p_k IN PLS_INTEGER) RETURN t_str IS
  BEGIN
    CASE p_k
      WHEN 0 THEN RETURN t_str('REGISTRADO');
      WHEN 1 THEN RETURN t_str('REGISTRADO','VALIDADO_COMISARIA');
      WHEN 2 THEN RETURN t_str('REGISTRADO','VALIDADO_COMISARIA','EN_INVESTIGACION');
      WHEN 3 THEN RETURN t_str('REGISTRADO','VALIDADO_COMISARIA','EN_INVESTIGACION','INTERVENCION_PROGRAMADA');
      WHEN 4 THEN RETURN t_str('REGISTRADO','VALIDADO_COMISARIA','EN_INVESTIGACION','DERIVADO_FISCALIA');
      WHEN 5 THEN RETURN t_str('REGISTRADO','VALIDADO_COMISARIA','EN_INVESTIGACION','INTERVENCION_PROGRAMADA',
                               'DERIVADO_FISCALIA','RESUELTO');
      ELSE        RETURN t_str('REGISTRADO','VALIDADO_COMISARIA','EN_INVESTIGACION','ARCHIVADO');
    END CASE;
  END get_path;

  FUNCTION reason_for(p_status IN VARCHAR2) RETURN VARCHAR2 IS
  BEGIN
    RETURN CASE p_status
      WHEN 'REGISTRADO'              THEN 'Denuncia registrada en el sistema por oficial de guardia'
      WHEN 'VALIDADO_COMISARIA'      THEN 'Validacion de los hechos y de la competencia por la comisaria'
      WHEN 'EN_INVESTIGACION'        THEN 'Asignacion de investigador titular y apertura de diligencias'
      WHEN 'INTERVENCION_PROGRAMADA' THEN 'Se identifico el punto de cobro y se programa intervencion'
      WHEN 'DERIVADO_FISCALIA'       THEN 'Se remite acta de investigacion al Ministerio Publico'
      WHEN 'RESUELTO'                THEN 'Caso esclarecido con captura y formalizacion de los responsables'
      ELSE                                'Archivo del caso por falta de elementos de conviccion'
    END;
  END reason_for;

  PROCEDURE add_assignment(p_complaint IN NUMBER, p_idx IN PLS_INTEGER, p_date IN TIMESTAMP,
                           p_end IN DATE, p_reason IN VARCHAR2, p_cip OUT VARCHAR2) IS
    v_try PLS_INTEGER := 0;
    v_k   PLS_INTEGER;
    v_by  VARCHAR2(15);
  BEGIN
    LOOP
      v_k  := MOD(p_idx + v_try, v_n_off) + 1;
      v_by := CASE WHEN v_k = 1 THEN v_cips(2) ELSE v_cips(1) END;   -- comisario distinto al detective
      BEGIN
        INSERT INTO TB_INV_ASSIGNMENT
          (complaint_id, officer_cip, assigned_by_cip, assignment_date, end_date, reassignment_reason)
        VALUES (p_complaint, v_cips(v_k), v_by, p_date, p_end, p_reason);
        p_cip := v_cips(v_k);
        RETURN;
      EXCEPTION WHEN OTHERS THEN
        IF SQLCODE = -20001 AND v_try < v_n_off THEN   -- cupo lleno: probar otro detective
          v_try := v_try + 1;
        ELSE
          RAISE;
        END IF;
      END;
    END LOOP;
  END add_assignment;

BEGIN
  SELECT officer_cip BULK COLLECT INTO v_cips FROM TB_STAFF_OFFICER ORDER BY officer_cip;
  v_n_off := v_cips.COUNT;
  IF v_n_off < 3 THEN
    RAISE_APPLICATION_ERROR(-20900, 'Se necesitan al menos 3 oficiales en TB_STAFF_OFFICER.');
  END IF;

  FOR c IN (SELECT complaint_id, sector_id, registration_date
              FROM TB_CPL_COMPLAINT cp
             WHERE NOT EXISTS (SELECT 1 FROM TB_INV_STATUS_HISTORY h WHERE h.complaint_id = cp.complaint_id)
             ORDER BY complaint_id
             FETCH FIRST 40 ROWS ONLY) LOOP

    v_i      := v_i + 1;
    v_path   := get_path(MOD(v_i, 7));
    v_last   := v_path(v_path.COUNT);
    v_closed := v_last IN ('ARCHIVADO','RESUELTO');
    v_base   := NVL(c.registration_date, v_now - NUMTODSINTERVAL(30, 'DAY'));
    v_det    := NULL;
    v_ts_inv := NULL;
    v_ts_int := NULL;

    FOR k IN 1 .. v_path.COUNT LOOP
      v_ts := v_base + NUMTODSINTERVAL(k - 1, 'DAY') + NUMTODSINTERVAL(MOD(v_i, 5) * 2, 'HOUR');
      IF v_ts > v_now THEN v_ts := v_now; END IF;
      IF v_path(k) = 'EN_INVESTIGACION'        THEN v_ts_inv := v_ts; END IF;
      IF v_path(k) = 'INTERVENCION_PROGRAMADA' THEN v_ts_int := v_ts; END IF;

      -- Al llegar a EN_INVESTIGACION se crean las asignaciones (la reasignacion de ejemplo en pares)
      IF v_path(k) = 'EN_INVESTIGACION' THEN
        IF MOD(v_i, 2) = 0 AND NOT v_closed THEN
          -- primera asignacion ya cerrada (reasignada) y segunda activa
          v_ts2 := v_ts + NUMTODSINTERVAL(1, 'HOUR');
          IF v_ts2 > v_now THEN v_ts2 := v_now; END IF;
          add_assignment(c.complaint_id, v_i, v_ts, CAST(v_ts2 AS DATE),
                         'Cambio de unidad del investigador inicial', v_actor);
          add_assignment(c.complaint_id, v_i + 1, v_ts2, NULL, NULL, v_det);
        ELSIF v_closed THEN
          add_assignment(c.complaint_id, v_i, v_ts, NULL, NULL, v_det);   -- se cierra al llegar al estado final
        ELSE
          add_assignment(c.complaint_id, v_i, v_ts, NULL, NULL, v_det);
        END IF;
      END IF;

      v_actor  := CASE WHEN v_det IS NULL THEN v_cips(1) ELSE v_det END;
      v_prev   := CASE WHEN k = 1 THEN NULL ELSE v_path(k - 1) END;
      v_reason := reason_for(v_path(k));          -- funcion local: se evalua FUERA del SQL
      INSERT INTO TB_INV_STATUS_HISTORY
        (complaint_id, officer_cip, previous_status, new_status, change_reason, change_timestamp)
      VALUES
        (c.complaint_id, v_actor, v_prev, v_path(k), v_reason, v_ts);
    END LOOP;

    -- Casos cerrados: se libera el cupo (el trigger descuenta active_case_count)
    IF v_closed THEN
      UPDATE TB_INV_ASSIGNMENT
         SET end_date = CAST(v_ts AS DATE)
       WHERE complaint_id = c.complaint_id AND end_date IS NULL;
    END IF;

    UPDATE TB_CPL_COMPLAINT SET current_status = v_last WHERE complaint_id = c.complaint_id;

    -- Equipo de apoyo en algunos casos con investigador
    IF v_det IS NOT NULL AND MOD(v_i, 3) = 0 THEN
      FOR s IN 1 .. 2 LOOP
        v_sup := v_cips(MOD(v_i + s, v_n_off) + 1);
        IF v_sup <> v_det THEN
          BEGIN
            INSERT INTO TB_INV_SUPPORT_TEAM (complaint_id, officer_cip)
            VALUES (c.complaint_id, v_sup);
          EXCEPTION WHEN DUP_VAL_ON_INDEX THEN NULL;
          END;
        END IF;
      END LOOP;
    END IF;

    -- Denuncias que ya pasaron por INTERVENCION y se resolvieron: operativo historico
    IF MOD(v_i, 7) = 5 THEN
      v_hist(v_hist.COUNT + 1) := c.complaint_id;
    END IF;
  END LOOP;

  -- Operativos historicos (ya ejecutados), insercion directa
  FOR h IN 1 .. v_hist.COUNT LOOP
    SELECT sector_id INTO v_dummy FROM TB_CPL_COMPLAINT WHERE complaint_id = v_hist(h);
    SELECT MIN(change_timestamp) INTO v_ts FROM TB_INV_STATUS_HISTORY
     WHERE complaint_id = v_hist(h) AND new_status = 'INTERVENCION_PROGRAMADA';
    INSERT INTO TB_OPS_OPERATION (sector_id, operation_type, operation_date)
    VALUES (v_dummy,
            CASE MOD(h, 2) WHEN 0 THEN 'Operativo de Flagrancia' ELSE 'Patrullaje Integrado' END,
            v_ts + NUMTODSINTERVAL(1, 'DAY'))
    RETURNING operation_id INTO v_op;
    INSERT INTO TB_OPS_OPERATION_COMPLAINT (operation_id, complaint_id) VALUES (v_op, v_hist(h));
    FOR s IN 1 .. 3 LOOP
      INSERT INTO TB_OPS_OPERATION_STAFF (operation_id, officer_cip) VALUES (v_op, v_cips(s));
    END LOOP;
  END LOOP;

  -- Operativos vigentes: uno por sector con denuncias en INTERVENCION_PROGRAMADA
  FOR s IN (SELECT DISTINCT sector_id FROM TB_CPL_COMPLAINT
             WHERE current_status = 'INTERVENCION_PROGRAMADA') LOOP
    INSERT INTO TB_OPS_OPERATION (sector_id, operation_type, operation_date)
    VALUES (s.sector_id, 'Intervencion Focalizada', v_now + NUMTODSINTERVAL(2, 'DAY'))
    RETURNING operation_id INTO v_op;
    INSERT INTO TB_OPS_OPERATION_COMPLAINT (operation_id, complaint_id)
      SELECT v_op, complaint_id FROM TB_CPL_COMPLAINT
       WHERE sector_id = s.sector_id AND current_status = 'INTERVENCION_PROGRAMADA';
    FOR k IN 1 .. 3 LOOP
      INSERT INTO TB_OPS_OPERATION_STAFF (operation_id, officer_cip) VALUES (v_op, v_cips(k));
    END LOOP;
  END LOOP;

  COMMIT;
  DBMS_OUTPUT.PUT_LINE('Carga completada. Denuncias procesadas: ' || v_i);
END;
/
