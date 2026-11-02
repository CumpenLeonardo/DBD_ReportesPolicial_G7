-- ===================================================================
-- GEO-DENUNCIA | Grupo 07 | Modulo INV (Investigacion, Asignacion y Operativos)
-- 07_inv_tests.sql : pruebas de restricciones, triggers y PKG_INV_MGMT.
--
-- PRERREQUISITOS (deben existir antes de ejecutar):
--   03_inv_ddl.sql, 04_inv_triggers.sql, 05b_inv_data.sql, 06_pkg_inv_mgmt.sql
--   Datos de prueba con al menos: 2 denuncias REGISTRADO, 2 VALIDADO_COMISARIA
--   y 1 INTERVENCION_PROGRAMADA (los deja 05b_inv_data.sql si hay >= 14 denuncias).
-- ===================================================================

SET SERVEROUTPUT ON SIZE UNLIMITED;

DECLARE
  v_pass  PLS_INTEGER := 0;
  v_fail  PLS_INTEGER := 0;
  v_code  NUMBER;
  v_cpl   NUMBER;
  v_cpl2  NUMBER;
  v_cip1  VARCHAR2(15);   -- comisario
  v_cip2  VARCHAR2(15);   -- detective 1
  v_cip3  VARCHAR2(15);   -- detective 2
  v_sec   NUMBER;
  v_tmp   NUMBER;
  v_op    NUMBER;
  v_cnt   NUMBER;
  v_st    VARCHAR2(30);
  v_old   VARCHAR2(100);
  v_c2    NUMBER;
  v_c3    NUMBER;

  PROCEDURE report(p_name IN VARCHAR2, p_ok IN BOOLEAN, p_detail IN VARCHAR2 DEFAULT NULL) IS
  BEGIN
    IF p_ok THEN
      v_pass := v_pass + 1;
      DBMS_OUTPUT.PUT_LINE('[PASS] ' || p_name);
    ELSE
      v_fail := v_fail + 1;
      DBMS_OUTPUT.PUT_LINE('[FAIL] ' || p_name || ' ' || p_detail);
    END IF;
  END report;

  PROCEDURE expect(p_name IN VARCHAR2, p_expected IN NUMBER, p_got IN NUMBER) IS
  BEGIN
    report(p_name || ' (esperado ' || p_expected || ')',
           p_got = p_expected, '-> obtenido ' || NVL(TO_CHAR(p_got), 'NULL'));
  END expect;

  PROCEDURE skip(p_name IN VARCHAR2) IS
  BEGIN
    DBMS_OUTPUT.PUT_LINE('[SKIP] ' || p_name || ' (no hay datos de prueba suficientes)');
  END skip;

  FUNCTION pick_complaint(p_status IN VARCHAR2) RETURN NUMBER IS
    v NUMBER;
  BEGIN
    SELECT complaint_id INTO v FROM TB_CPL_COMPLAINT
     WHERE current_status = p_status
     ORDER BY complaint_id FETCH FIRST 1 ROW ONLY;
    RETURN v;
  EXCEPTION WHEN NO_DATA_FOUND THEN
    RETURN NULL;
  END pick_complaint;

  FUNCTION active_count(p_cip IN VARCHAR2) RETURN NUMBER IS
    v NUMBER;
  BEGIN
    SELECT NVL(active_case_count, 0) INTO v FROM TB_STAFF_OFFICER WHERE officer_cip = p_cip;
    RETURN v;
  END active_count;

BEGIN
  SELECT officer_cip INTO v_cip1 FROM TB_STAFF_OFFICER ORDER BY officer_cip OFFSET 0 ROWS FETCH NEXT 1 ROWS ONLY;
  SELECT officer_cip INTO v_cip2 FROM TB_STAFF_OFFICER ORDER BY officer_cip OFFSET 1 ROWS FETCH NEXT 1 ROWS ONLY;
  SELECT officer_cip INTO v_cip3 FROM TB_STAFF_OFFICER ORDER BY officer_cip OFFSET 2 ROWS FETCH NEXT 1 ROWS ONLY;

  DBMS_OUTPUT.PUT_LINE('=== A. Historial inmutable ===');

  v_code := 0;
  BEGIN
    UPDATE TB_INV_STATUS_HISTORY SET change_reason = 'modificado' WHERE ROWNUM = 1;
  EXCEPTION WHEN OTHERS THEN v_code := SQLCODE;
  END;
  expect('T01 UPDATE sobre el historial bloqueado', -20010, v_code);

  v_code := 0;
  BEGIN
    DELETE FROM TB_INV_STATUS_HISTORY WHERE ROWNUM = 1;
  EXCEPTION WHEN OTHERS THEN v_code := SQLCODE;
  END;
  expect('T02 DELETE sobre el historial bloqueado', -20010, v_code);

  DBMS_OUTPUT.PUT_LINE('=== B. change_status ===');

  v_cpl := pick_complaint('REGISTRADO');
  IF v_cpl IS NULL THEN
    skip('T03-T06');
  ELSE
    v_code := 0;
    BEGIN
      PKG_INV_MGMT.change_status(v_cpl, 'RESUELTO', v_cip1, 'Intento de salto invalido');
    EXCEPTION WHEN OTHERS THEN v_code := SQLCODE;
    END;
    expect('T03 salto REGISTRADO -> RESUELTO rechazado', -20021, v_code);

    v_code := 0;
    BEGIN
      PKG_INV_MGMT.change_status(v_cpl, 'VALIDADO_COMISARIA', v_cip1, NULL);
    EXCEPTION WHEN OTHERS THEN v_code := SQLCODE;
    END;
    expect('T04 observaciones nulas rechazadas', -20020, v_code);

    v_code := 0;
    BEGIN
      PKG_INV_MGMT.change_status(v_cpl, 'VALIDADO_COMISARIA', v_cip1, 'corto');
    EXCEPTION WHEN OTHERS THEN v_code := SQLCODE;
    END;
    expect('T05 observaciones demasiado cortas rechazadas', -20020, v_code);

    v_code := 0;
    BEGIN
      PKG_INV_MGMT.change_status(v_cpl, 'VALIDADO_COMISARIA', v_cip1, 'Validacion de prueba automatizada');
    EXCEPTION WHEN OTHERS THEN v_code := SQLCODE;
    END;
    SELECT current_status INTO v_st FROM TB_CPL_COMPLAINT WHERE complaint_id = v_cpl;
    SELECT COUNT(*) INTO v_cnt FROM TB_INV_STATUS_HISTORY
     WHERE complaint_id = v_cpl AND previous_status = 'REGISTRADO'
       AND new_status = 'VALIDADO_COMISARIA' AND change_reason LIKE 'Validacion de prueba%';
    report('T06 transicion valida actualiza estado e historial',
           v_code = 0 AND v_st = 'VALIDADO_COMISARIA' AND v_cnt = 1,
           '-> codigo ' || v_code || ', estado ' || v_st || ', filas historial ' || v_cnt);
  END IF;

  DBMS_OUTPUT.PUT_LINE('=== C. Asignacion de investigador ===');

  -- v_cpl quedo en VALIDADO_COMISARIA tras T06
  IF v_cpl IS NULL THEN
    skip('T07-T13');
  ELSE
    v_c2 := active_count(v_cip2);
    v_c3 := active_count(v_cip3);

    v_code := 0;
    BEGIN
      v_tmp := PKG_INV_MGMT.assign_investigator(v_cpl, v_cip2, v_cip1);
    EXCEPTION WHEN OTHERS THEN v_code := SQLCODE;
    END;
    SELECT current_status INTO v_st FROM TB_CPL_COMPLAINT WHERE complaint_id = v_cpl;
    report('T07 asignar pasa la denuncia a EN_INVESTIGACION y sube el contador',
           v_code = 0 AND v_st = 'EN_INVESTIGACION' AND active_count(v_cip2) = v_c2 + 1,
           '-> codigo ' || v_code || ', estado ' || v_st);

    v_code := 0;
    BEGIN
      INSERT INTO TB_INV_ASSIGNMENT (complaint_id, officer_cip, assigned_by_cip)
      VALUES (v_cpl, v_cip3, v_cip1);
    EXCEPTION WHEN OTHERS THEN v_code := SQLCODE;
    END;
    expect('T08 segundo titular activo rechazado (indice unico)', -1, v_code);

    v_code := 0;
    BEGIN
      v_tmp := PKG_INV_MGMT.assign_investigator(v_cpl, v_cip3, v_cip1, NULL);
    EXCEPTION WHEN OTHERS THEN v_code := SQLCODE;
    END;
    expect('T09 reasignacion sin motivo rechazada', -20033, v_code);

    v_code := 0;
    BEGIN
      v_tmp := PKG_INV_MGMT.assign_investigator(v_cpl, v_cip2, v_cip1, 'Motivo de prueba suficientemente largo');
    EXCEPTION WHEN OTHERS THEN v_code := SQLCODE;
    END;
    expect('T10 reasignar al mismo titular rechazado', -20032, v_code);

    v_code := 0;
    BEGIN
      v_tmp := PKG_INV_MGMT.assign_investigator(v_cpl, v_cip3, v_cip1, 'Reasignacion de prueba por rotacion');
    EXCEPTION WHEN OTHERS THEN v_code := SQLCODE;
    END;
    SELECT COUNT(*) INTO v_cnt FROM TB_INV_ASSIGNMENT WHERE complaint_id = v_cpl AND end_date IS NULL;
    SELECT COUNT(*) INTO v_tmp FROM TB_INV_ASSIGNMENT WHERE complaint_id = v_cpl AND end_date IS NOT NULL
       AND reassignment_reason LIKE 'Reasignacion de prueba%';
    report('T11 reasignacion cierra la anterior y deja un solo titular activo',
           v_code = 0 AND v_cnt = 1 AND v_tmp = 1
           AND active_count(v_cip2) = v_c2 AND active_count(v_cip3) = v_c3 + 1,
           '-> codigo ' || v_code || ', activas ' || v_cnt || ', cerradas ' || v_tmp);
  END IF;

  v_cpl2 := pick_complaint('REGISTRADO');
  IF v_cpl2 IS NULL THEN
    skip('T12');
  ELSE
    v_code := 0;
    BEGIN
      INSERT INTO TB_INV_ASSIGNMENT (complaint_id, officer_cip, assigned_by_cip)
      VALUES (v_cpl2, v_cip2, v_cip2);
    EXCEPTION WHEN OTHERS THEN v_code := SQLCODE;
    END;
    expect('T12 detective no puede firmar su propia asignacion (CHECK)', -2290, v_code);
  END IF;

  v_cpl2 := pick_complaint('VALIDADO_COMISARIA');
  IF v_cpl2 IS NULL THEN
    skip('T13');
  ELSE
    SELECT param_value INTO v_old FROM TB_CFG_PARAMETER WHERE param_name = 'MAX_ACTIVE_CASES';
    UPDATE TB_CFG_PARAMETER SET param_value = '0' WHERE param_name = 'MAX_ACTIVE_CASES';
    v_code := 0;
    BEGIN
      v_tmp := PKG_INV_MGMT.assign_investigator(v_cpl2, v_cip2, v_cip1);
    EXCEPTION WHEN OTHERS THEN v_code := SQLCODE;
    END;
    UPDATE TB_CFG_PARAMETER SET param_value = v_old WHERE param_name = 'MAX_ACTIVE_CASES';
    expect('T13 limite N de casos activos bloquea la asignacion', -20001, v_code);
  END IF;

  DBMS_OUTPUT.PUT_LINE('=== D. Cierre de caso ===');

  IF v_cpl IS NULL THEN
    skip('T14-T15');
  ELSE
    v_c3 := active_count(v_cip3);
    v_code := 0;
    BEGIN
      PKG_INV_MGMT.change_status(v_cpl, 'ARCHIVADO', v_cip3, 'Archivo de prueba por falta de elementos');
    EXCEPTION WHEN OTHERS THEN v_code := SQLCODE;
    END;
    SELECT COUNT(*) INTO v_cnt FROM TB_INV_ASSIGNMENT WHERE complaint_id = v_cpl AND end_date IS NULL;
    report('T14 archivar cierra la asignacion y libera el cupo',
           v_code = 0 AND v_cnt = 0 AND active_count(v_cip3) = v_c3 - 1,
           '-> codigo ' || v_code || ', activas ' || v_cnt);

    v_code := 0;
    BEGIN
      PKG_INV_MGMT.change_status(v_cpl, 'EN_INVESTIGACION', v_cip1, 'Intento de reabrir un caso archivado');
    EXCEPTION WHEN OTHERS THEN v_code := SQLCODE;
    END;
    expect('T15 ARCHIVADO es estado terminal', -20021, v_code);
  END IF;

  DBMS_OUTPUT.PUT_LINE('=== E. Operativos ===');

  v_cpl2 := pick_complaint('INTERVENCION_PROGRAMADA');
  IF v_cpl2 IS NULL OR v_cpl IS NULL THEN
    skip('T16-T18');
  ELSE
    -- denuncia ARCHIVADA (v_cpl) no puede entrar a un operativo
    SELECT sector_id INTO v_sec FROM TB_CPL_COMPLAINT WHERE complaint_id = v_cpl;
    v_code := 0;
    BEGIN
      v_op := PKG_INV_MGMT.register_operation(v_sec, 'Prueba', SYSTIMESTAMP,
                PKG_INV_MGMT.t_id_list(v_cpl), PKG_INV_MGMT.t_cip_list(v_cip1));
    EXCEPTION WHEN OTHERS THEN v_code := SQLCODE;
    END;
    expect('T16 operativo con denuncia fuera de INTERVENCION_PROGRAMADA rechazado', -20040, v_code);

    SELECT sector_id INTO v_sec FROM TB_CPL_COMPLAINT WHERE complaint_id = v_cpl2;
    v_code := 0;
    BEGIN
      v_op := PKG_INV_MGMT.register_operation(v_sec, 'Prueba', SYSTIMESTAMP,
                PKG_INV_MGMT.t_id_list(v_cpl2), PKG_INV_MGMT.t_cip_list(v_cip1, v_cip2));
    EXCEPTION WHEN OTHERS THEN v_code := SQLCODE;
    END;
    SELECT COUNT(*) INTO v_cnt FROM TB_OPS_OPERATION_COMPLAINT WHERE operation_id = v_op;
    SELECT COUNT(*) INTO v_tmp FROM TB_OPS_OPERATION_STAFF     WHERE operation_id = v_op;
    report('T17 register_operation crea cabecera, 1 denuncia y 2 efectivos',
           v_code = 0 AND v_cnt = 1 AND v_tmp = 2,
           '-> codigo ' || v_code || ', denuncias ' || v_cnt || ', efectivos ' || v_tmp);

    IF v_op IS NULL THEN
      skip('T18');
    ELSE
      PKG_INV_MGMT.delete_operation(v_op);
      SELECT COUNT(*) INTO v_cnt FROM TB_OPS_OPERATION_COMPLAINT WHERE operation_id = v_op;
      SELECT COUNT(*) INTO v_tmp FROM TB_OPS_OPERATION_STAFF     WHERE operation_id = v_op;
      report('T18 borrar el operativo elimina en cascada sus relaciones',
             v_cnt = 0 AND v_tmp = 0, '-> denuncias ' || v_cnt || ', efectivos ' || v_tmp);
    END IF;
  END IF;

  DBMS_OUTPUT.PUT_LINE('=== F. Consistencia global ===');

  SELECT COUNT(*) INTO v_cnt
    FROM TB_STAFF_OFFICER o
   WHERE NVL(o.active_case_count, 0) <>
         (SELECT COUNT(*) FROM TB_INV_ASSIGNMENT a
           WHERE a.officer_cip = o.officer_cip AND a.end_date IS NULL);
  expect('T19 active_case_count coincide con las asignaciones activas (filas con diferencia)', 0, v_cnt);

  SELECT COUNT(*) INTO v_cnt
    FROM TB_CPL_COMPLAINT c
   WHERE EXISTS (SELECT 1 FROM TB_INV_STATUS_HISTORY h WHERE h.complaint_id = c.complaint_id)
     AND c.current_status <> (SELECT h.new_status FROM TB_INV_STATUS_HISTORY h
                               WHERE h.history_id = (SELECT MAX(h2.history_id) FROM TB_INV_STATUS_HISTORY h2
                                                      WHERE h2.complaint_id = c.complaint_id));
  expect('T20 current_status coincide con el ultimo evento del historial (filas con diferencia)', 0, v_cnt);

  SELECT COUNT(*) INTO v_cnt
    FROM (SELECT complaint_id FROM TB_INV_ASSIGNMENT WHERE end_date IS NULL
           GROUP BY complaint_id HAVING COUNT(*) > 1);
  expect('T21 ninguna denuncia con mas de un titular activo', 0, v_cnt);

  DBMS_OUTPUT.PUT_LINE('-------------------------------------------');
  DBMS_OUTPUT.PUT_LINE('Resultado: ' || v_pass || ' PASS, ' || v_fail || ' FAIL');
  ROLLBACK;   -- las pruebas no dejan cambios
END;
/

-- Conteo de filas por tabla (para el informe)
SELECT 'TB_INV_ASSIGNMENT' AS tabla, COUNT(*) AS filas FROM TB_INV_ASSIGNMENT UNION ALL
SELECT 'TB_INV_SUPPORT_TEAM',        COUNT(*) FROM TB_INV_SUPPORT_TEAM UNION ALL
SELECT 'TB_INV_STATUS_HISTORY',      COUNT(*) FROM TB_INV_STATUS_HISTORY UNION ALL
SELECT 'TB_OPS_OPERATION',           COUNT(*) FROM TB_OPS_OPERATION UNION ALL
SELECT 'TB_OPS_OPERATION_COMPLAINT', COUNT(*) FROM TB_OPS_OPERATION_COMPLAINT UNION ALL
SELECT 'TB_OPS_OPERATION_STAFF',     COUNT(*) FROM TB_OPS_OPERATION_STAFF;
