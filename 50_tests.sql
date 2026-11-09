-- =============================================================================
-- 50_tests.sql
-- Pruebas automáticas de organización, denuncias e investigación sobre pkg_org_mgmt, pkg_cpl_mgmt y pkg_inv_mgmt.
-- Ejecutar como GEO_OWNER. Todas las pruebas terminan con ROLLBACK y no modifican los datos.
-- =============================================================================

-- =============================================================================
-- SECCION 1: Pruebas de organización (moneda, territorio y personal)
-- Imprime PASS o FAIL por caso y un resumen. Los errores esperados se comparan con SQLCODE:
--   -20001 no encontrado | -20002 dato inválido | -2290 CHECK violado | -2292 FK con hijos
-- =============================================================================
SET SERVEROUTPUT ON SIZE UNLIMITED

DECLARE
  v_pass NUMBER := 0;
  v_fail NUMBER := 0;
  v_id   NUMBER;
  v_id2  NUMBER;

  PROCEDURE check_that (p_name IN VARCHAR2, p_ok IN BOOLEAN) IS
  BEGIN
    IF p_ok THEN v_pass := v_pass + 1; ELSE v_fail := v_fail + 1; END IF;
    DBMS_OUTPUT.PUT_LINE(CASE WHEN p_ok THEN 'PASS  ' ELSE 'FAIL  ' END || p_name);
  END check_that;
BEGIN
  SAVEPOINT before_tests;

  -- T01: 100 USD x 3.75 = 375 soles.
  check_that('T01 convert_to_pen USD', pkg_org_mgmt.convert_to_pen(100, 2) = 375);

  -- T02: la tasa de PEN no se puede cambiar.
  BEGIN
    pkg_org_mgmt.update_currency(1, 'Peruvian Sol', 2);
    check_that('T02 PEN rate cannot change', FALSE);
  EXCEPTION WHEN OTHERS THEN
    check_that('T02 PEN rate cannot change', SQLCODE = -20002);
  END;

  -- T03: moneda inexistente.
  BEGIN
    v_id := pkg_org_mgmt.convert_to_pen(10, 999);
    check_that('T03 unknown currency raises not found', FALSE);
  EXCEPTION WHEN OTHERS THEN
    check_that('T03 unknown currency raises not found', SQLCODE = -20001);
  END;

  -- T04: se crea división, comisaría y sector, y el sector nuevo se encuentra por GPS
  -- (comprueba que el polígono y el índice espacial funcionan).
  pkg_org_mgmt.insert_division('DIVPOL TEST', 'REGION TEST', v_id);
  pkg_org_mgmt.insert_station(v_id, 'COMISARIA TEST', 'Calle Falsa 123', v_id2);
  pkg_org_mgmt.insert_sector(v_id2, 'SECTOR TEST', -12.10, -12.09, -77.10, -77.09, v_id);
  check_that('T04 new sector is found by GPS', pkg_org_mgmt.find_sector_by_location(-12.095, -77.095) = v_id);

  -- T05: no se borra una comisaría que tiene sectores.
  BEGIN
    pkg_org_mgmt.delete_station(v_id2);
    check_that('T05 station with sectors cannot be deleted', FALSE);
  EXCEPTION WHEN OTHERS THEN
    check_that('T05 station with sectors cannot be deleted', SQLCODE = -2292);
  END;

  -- T06: actualizar una comisaría que no existe.
  BEGIN
    pkg_org_mgmt.update_station(999999, 1, 'X', 'X');
    check_that('T06 unknown station raises not found', FALSE);
  EXCEPTION WHEN OTHERS THEN
    check_that('T06 unknown station raises not found', SQLCODE = -20001);
  END;

  -- T07: punto dentro del sector 1.
  check_that('T07 point inside sector 1', pkg_org_mgmt.find_sector_by_location(-11.975, -76.995) = 1);

  -- T08: latitud -11.970 es el borde entre los sectores 1 y 3: pertenece solo al 3.
  check_that('T08 shared edge belongs to one sector', pkg_org_mgmt.find_sector_by_location(-11.970, -76.995) = 3);

  -- T09: punto fuera de todos los sectores.
  check_that('T09 point outside returns NULL', pkg_org_mgmt.find_sector_by_location(-13.5, -75.0) IS NULL);

  -- T10: un capitán (nivel 3) no puede tener como superior a un suboficial (nivel 5).
  BEGIN
    pkg_org_mgmt.insert_officer('90000001', 'Bad', 'Rank', 3, 1, '10000009', 'ORDEN_PUBLICO');
    check_that('T10 supervisor with lower rank is rejected', FALSE);
  EXCEPTION WHEN OTHERS THEN
    check_that('T10 supervisor with lower rank is rejected', SQLCODE = -20002);
  END;

  -- T11: un efectivo no puede ser su propio superior (CHECK de la tabla).
  BEGIN
    UPDATE tb_staff_officer SET supervisor_cip = officer_cip WHERE officer_cip = '10000009';
    check_that('T11 officer cannot supervise himself', FALSE);
  EXCEPTION WHEN OTHERS THEN
    check_that('T11 officer cannot supervise himself', SQLCODE = -2290);
  END;

  -- T12: no se borra un efectivo que tiene subordinados.
  BEGIN
    pkg_org_mgmt.delete_officer('10000003');
    check_that('T12 officer with subordinates cannot be deleted', FALSE);
  EXCEPTION WHEN OTHERS THEN
    check_that('T12 officer with subordinates cannot be deleted', SQLCODE = -2292);
  END;

  ROLLBACK TO before_tests;
  DBMS_OUTPUT.PUT_LINE('Passed: ' || v_pass || ' | Failed: ' || v_fail);
END;
/

-- =============================================================================
-- SECCION 2: Pruebas de denuncias, anonimato, evidencias y reportes
-- Imprime [OK] o [FALLA] por caso. Los datos de apoyo se leen de las tablas.
-- =============================================================================
SET SERVEROUTPUT ON SIZE UNLIMITED


-- =====================================================================
-- PARTE A: PRUEBAS FUNCIONALES
-- =====================================================================
DECLARE
  v_cip        tb_staff_officer.officer_cip%TYPE;
  v_lat        NUMBER;
  v_lon        NUMBER;
  v_lat2       NUMBER;
  v_lon2       NUMBER;
  v_sector2    NUMBER;
  v_mod        NUMBER;
  v_rate_usd   NUMBER;
  v_rate_eur   NUMBER;
  v_id_ord     NUMBER;
  v_id_anon    NUMBER;
  v_id_aux     NUMBER;
  v_new_mod    NUMBER;
  v_ev         NUMBER;
  v_cnt1       NUMBER;
  v_cnt2       NUMBER;
  v_cmp        tb_cpl_complaint%ROWTYPE;
  v_prot       tb_cpl_complaint_protection%ROWTYPE;
  v_modrow     tb_cpl_modality%ROWTYPE;
  v_evrow      tb_cpl_digital_evidence%ROWTYPE;
  v_display    VARCHAR2(200);

  -- Variables para leer el cursor variable de list_complaints
  v_rc         SYS_REFCURSOR;
  l_id         NUMBER;
  l_sector     VARCHAR2(100);
  l_modality   VARCHAR2(80);
  l_date       TIMESTAMP;
  l_status     VARCHAR2(30);
  l_rep_name   VARCHAR2(110);
  l_rep_doc    VARCHAR2(20);
  l_cur        VARCHAR2(3);
  l_amt        NUMBER;
  l_pen        NUMBER;
  l_addr       VARCHAR2(200);
  l_lat        NUMBER;
  l_lon        NUMBER;

  v_ok         PLS_INTEGER := 0;
  v_ko         PLS_INTEGER := 0;

  PROCEDURE check_true (p_cond BOOLEAN, p_msg VARCHAR2) IS
  BEGIN
    IF p_cond THEN
      v_ok := v_ok + 1;
      DBMS_OUTPUT.PUT_LINE('[OK]    ' || p_msg);
    ELSE
      v_ko := v_ko + 1;
      DBMS_OUTPUT.PUT_LINE('[FALLA] ' || p_msg);
    END IF;
  END;

  -- Se llama desde un manejador de excepciones con SQLCODE y SQLERRM
  PROCEDURE check_error (p_got NUMBER, p_expected NUMBER, p_msg VARCHAR2, p_err VARCHAR2) IS
  BEGIN
    check_true(p_got = p_expected,
               p_msg || ' -> ' || SUBSTR(REPLACE(p_err, CHR(10), ' '), 1, 110));
  END;

  PROCEDURE no_error (p_msg VARCHAR2) IS
  BEGIN
    check_true(FALSE, p_msg || ' -> se esperaba un error y no ocurrio');
  END;

BEGIN
  -- Datos de apoyo (independientes de los valores concretos cargados)
  SELECT MIN(officer_cip) INTO v_cip FROM tb_staff_officer;
  SELECT MIN(modality_id) INTO v_mod FROM tb_cpl_modality;
  SELECT exchange_rate_pen INTO v_rate_usd FROM tb_cfg_currency WHERE currency_id = 2;
  SELECT exchange_rate_pen INTO v_rate_eur FROM tb_cfg_currency WHERE currency_id = 3;

  -- Centro del primer sector y centro del ultimo sector
  SELECT ROUND((min_lat + max_lat) / 2, 7), ROUND((min_lon + max_lon) / 2, 7)
    INTO v_lat, v_lon
    FROM tb_terr_sector
   WHERE sector_id = (SELECT MIN(sector_id) FROM tb_terr_sector);

  SELECT sector_id, ROUND((min_lat + max_lat) / 2, 7), ROUND((min_lon + max_lon) / 2, 7)
    INTO v_sector2, v_lat2, v_lon2
    FROM tb_terr_sector
   WHERE sector_id = (SELECT MAX(sector_id) FROM tb_terr_sector);

  DBMS_OUTPUT.PUT_LINE('=========== PRUEBAS pkg_cpl_mgmt ===========');

  -- T01 Denuncia ordinaria ------------------------------------------------
  v_id_ord := pkg_cpl_mgmt.register_complaint(
                p_is_anonymous      => 'N',
                p_document_id       => '45678912',
                p_first_name        => 'Mario',
                p_last_name         => 'Salas Ruiz',
                p_gender            => 'H',
                p_address           => 'Av. Wiesse 1500, SJL',
                p_phone             => '912345678',
                p_modality_id       => v_mod,
                p_incident_date     => LOCALTIMESTAMP - INTERVAL '1' DAY,
                p_latitude          => v_lat,
                p_longitude         => v_lon,
                p_incident_address  => 'Av. Wiesse cdra. 15',
                p_currency_id       => 2,
                p_amount_original   => 300,
                p_payment_frequency => 'SEMANALMENTE');
  v_cmp := pkg_cpl_mgmt.get_complaint(v_id_ord);

  check_true(v_cmp.id_reporter IS NOT NULL AND v_cmp.protected_code IS NULL,
             'T01 Ordinaria: guarda id_reporter y no codigo protegido (id ' || v_id_ord || ')');
  check_true(v_cmp.sector_id IS NOT NULL,
             'T01 Sector asignado automaticamente por GPS: ' || v_cmp.sector_id);
  check_true(v_cmp.amount_pen = ROUND(300 * v_rate_usd, 2),
             'T01 Conversion: 300 USD = ' || v_cmp.amount_pen || ' PEN');
  check_true(v_cmp.incident_location IS NOT NULL,
             'T01 Geometria generada por el trigger');
  DBMS_OUTPUT.PUT_LINE('        Denunciante mostrado: ' || pkg_cpl_mgmt.reporter_display(v_id_ord));

  -- T02 Denuncia anonima con enmascaramiento -----------------------------
  v_id_anon := pkg_cpl_mgmt.register_complaint(
                 p_is_anonymous     => 'Y',
                 p_document_id      => '47896541',
                 p_first_name       => 'Teresa',
                 p_last_name        => 'Paredes Luna',
                 p_gender           => 'M',
                 p_address          => 'Jr. Los Amautas 220, SJL',
                 p_phone            => '998877665',
                 p_modality_id      => v_mod,
                 p_incident_date    => LOCALTIMESTAMP - INTERVAL '3' DAY,
                 p_latitude         => v_lat,
                 p_longitude        => v_lon,
                 p_incident_address => 'Jr. Los Amautas cdra. 2',
                 p_amount_original  => 150,
                 p_officer_cip      => v_cip);
  v_cmp  := pkg_cpl_mgmt.get_complaint(v_id_anon);
  v_prot := pkg_cpl_mgmt.get_protection(v_cmp.protected_code);
  v_display := pkg_cpl_mgmt.reporter_display(v_id_anon);

  check_true(v_cmp.id_reporter IS NULL AND v_cmp.protected_code IS NOT NULL,
             'T02 Anonima: la denuncia NO guarda id_reporter, solo el codigo ' || v_cmp.protected_code);
  check_true(v_prot.id_reporter IS NOT NULL AND v_prot.approved_by_officer = v_cip,
             'T02 La identidad real queda solo en la proteccion (aprobada por ' || v_cip || ')');
  check_true(v_display LIKE '%RESERVADA%',
             'T02 Enmascaramiento: ' || v_display);

  -- T03 Reutilizacion del denunciante por documento ----------------------
  SELECT COUNT(*) INTO v_cnt1 FROM tb_cpl_reporter;
  v_id_aux := pkg_cpl_mgmt.register_complaint(
                p_is_anonymous     => 'N',
                p_document_id      => '45678912',
                p_first_name       => 'Mario',
                p_last_name        => 'Salas Ruiz',
                p_gender           => 'H',
                p_address          => 'Av. Wiesse 1500, SJL',
                p_phone            => '912345678',
                p_modality_id      => v_mod,
                p_incident_date    => LOCALTIMESTAMP - INTERVAL '1' DAY,
                p_latitude         => v_lat,
                p_longitude        => v_lon,
                p_incident_address => 'Av. Wiesse cdra. 16');
  SELECT COUNT(*) INTO v_cnt2 FROM tb_cpl_reporter;
  check_true(v_cnt1 = v_cnt2,
             'T03 Mismo DNI: se reutiliza el denunciante (' || v_cnt1 || ' = ' || v_cnt2 || ')');

  -- T04 Anonima sin oficial: debe fallar con -20114 ----------------------
  BEGIN
    v_id_aux := pkg_cpl_mgmt.register_complaint(
                  p_is_anonymous => 'Y', p_document_id => '41111111',
                  p_first_name => 'X', p_last_name => 'Y', p_gender => 'H',
                  p_address => 'Z', p_phone => '900000000', p_modality_id => v_mod,
                  p_incident_date => LOCALTIMESTAMP, p_latitude => v_lat,
                  p_longitude => v_lon, p_incident_address => 'Z');
    no_error('T04 Anonima sin oficial');
  EXCEPTION
    WHEN OTHERS THEN check_error(SQLCODE, -20114, 'T04 Anonima sin oficial', SQLERRM);
  END;

  -- T05 Punto fuera de todo sector: debe fallar con -20113 ---------------
  BEGIN
    v_id_aux := pkg_cpl_mgmt.register_complaint(
                  p_is_anonymous => 'N', p_document_id => '42222222',
                  p_first_name => 'X', p_last_name => 'Y', p_gender => 'H',
                  p_address => 'Z', p_phone => '900000000', p_modality_id => v_mod,
                  p_incident_date => LOCALTIMESTAMP, p_latitude => 0,
                  p_longitude => 0, p_incident_address => 'Z');
    no_error('T05 Punto fuera de sector');
  EXCEPTION
    WHEN OTHERS THEN check_error(SQLCODE, -20113, 'T05 Punto fuera de sector', SQLERRM);
  END;

  -- T06 Moneda inexistente: -20101 y el SAVEPOINT deshace el denunciante --
  BEGIN
    v_id_aux := pkg_cpl_mgmt.register_complaint(
                  p_is_anonymous => 'N', p_document_id => '43333333',
                  p_first_name => 'Pedro', p_last_name => 'Prueba', p_gender => 'H',
                  p_address => 'Z', p_phone => '900000000', p_modality_id => v_mod,
                  p_incident_date => LOCALTIMESTAMP, p_latitude => v_lat,
                  p_longitude => v_lon, p_incident_address => 'Z',
                  p_currency_id => 9, p_amount_original => 100);
    no_error('T06 Moneda inexistente');
  EXCEPTION
    WHEN OTHERS THEN check_error(SQLCODE, -20101, 'T06 Moneda inexistente', SQLERRM);
  END;
  SELECT COUNT(*) INTO v_cnt1 FROM tb_cpl_reporter WHERE personal_document_id = '43333333';
  check_true(v_cnt1 = 0,
             'T06 Atomicidad: el denunciante insertado antes del error fue deshecho');

  -- T07 Edicion: nuevo monto en EUR, el trigger recalcula amount_pen ------
  pkg_cpl_mgmt.upd_complaint(v_id_ord, v_mod, 3, 400, 'MENSUALMENTE', 'Los Pulpos', NULL, NULL);
  v_cmp := pkg_cpl_mgmt.get_complaint(v_id_ord);
  check_true(v_cmp.amount_pen = ROUND(400 * v_rate_eur, 2),
             'T07 Edicion: 400 EUR = ' || v_cmp.amount_pen || ' PEN');

  -- T08 Cambio de ubicacion: recalcula el sector -------------------------
  pkg_cpl_mgmt.upd_complaint_location(v_id_ord, v_lat2, v_lon2, 'Nueva direccion de prueba');
  v_cmp := pkg_cpl_mgmt.get_complaint(v_id_ord);
  check_true(v_cmp.sector_id = v_sector2,
             'T08 Reubicacion: sector recalculado a ' || v_cmp.sector_id);

  -- T09 Denuncia que ya avanzo de estado: no editable (-20118) ------------
  UPDATE tb_cpl_complaint SET current_status = 'VALIDADO_COMISARIA'
   WHERE complaint_id = v_id_ord;    -- simula el avance de estado
  BEGIN
    pkg_cpl_mgmt.upd_complaint(v_id_ord, v_mod, 1, 50, NULL, NULL, NULL, NULL);
    no_error('T09 Edicion fuera de REGISTRADO');
  EXCEPTION
    WHEN OTHERS THEN check_error(SQLCODE, -20118, 'T09 Edicion fuera de REGISTRADO', SQLERRM);
  END;

  -- T10 CRUD completo de modalidad ---------------------------------------
  v_new_mod := pkg_cpl_mgmt.ins_modality('Modalidad de prueba', 'HIGH');
  pkg_cpl_mgmt.upd_modality(v_new_mod, 'Modalidad de prueba editada', 'CRITICAL');
  v_modrow := pkg_cpl_mgmt.get_modality(v_new_mod);
  check_true(v_modrow.severity_level = 'CRITICAL',
             'T10 CRUD modalidad: insertar, actualizar y leer (' || v_modrow.modality_name || ')');
  pkg_cpl_mgmt.del_modality(v_new_mod);
  BEGIN
    v_modrow := pkg_cpl_mgmt.get_modality(v_new_mod);
    no_error('T10 Leer modalidad eliminada');
  EXCEPTION
    WHEN OTHERS THEN check_error(SQLCODE, -20110, 'T10 Leer modalidad eliminada', SQLERRM);
  END;

  -- T11 Modalidad duplicada (UK): -20115 ----------------------------------
  BEGIN
    v_new_mod := pkg_cpl_mgmt.ins_modality('Cobro de cupo', 'CRITICAL');
    no_error('T11 Modalidad duplicada');
  EXCEPTION
    WHEN OTHERS THEN check_error(SQLCODE, -20115, 'T11 Modalidad duplicada', SQLERRM);
  END;

  -- T12 Eliminar modalidad en uso (FK hija): -20111 -----------------------
  BEGIN
    pkg_cpl_mgmt.del_modality(v_mod);
    no_error('T12 Eliminar modalidad en uso');
  EXCEPTION
    WHEN OTHERS THEN check_error(SQLCODE, -20111, 'T12 Eliminar modalidad en uso', SQLERRM);
  END;

  -- T13 CRUD de evidencia -------------------------------------------------
  v_ev := pkg_cpl_mgmt.ins_evidence(v_id_anon, v_cip, 'FOTO',
                                    '/evidencias/prueba.jpg', 'Foto de prueba');
  pkg_cpl_mgmt.upd_evidence(v_ev, 'SCREENSHOT', '/evidencias/prueba.png',
                            'Captura de prueba');
  v_evrow := pkg_cpl_mgmt.get_evidence(v_ev);
  check_true(v_evrow.evidence_type = 'SCREENSHOT',
             'T13 CRUD evidencia: insertar, actualizar y leer (id ' || v_ev || ')');

  -- T14 Tipo de evidencia invalido (CHECK): -20116 ------------------------
  BEGIN
    pkg_cpl_mgmt.upd_evidence(v_ev, 'VIDEO_4K', '/x', 'x');
    no_error('T14 Tipo de evidencia invalido');
  EXCEPTION
    WHEN OTHERS THEN check_error(SQLCODE, -20116, 'T14 Tipo de evidencia invalido', SQLERRM);
  END;

  -- T15 Eliminar denuncia anonima: borra evidencias y proteccion ---------
  pkg_cpl_mgmt.del_complaint(v_id_anon);
  SELECT COUNT(*) INTO v_cnt1 FROM tb_cpl_complaint_protection
   WHERE protected_code = v_prot.protected_code;
  SELECT COUNT(*) INTO v_cnt2 FROM tb_cpl_digital_evidence WHERE complaint_id = v_id_anon;
  check_true(v_cnt1 = 0 AND v_cnt2 = 0,
             'T15 Baja de denuncia: se eliminaron su proteccion y sus evidencias');

  -- T16 Listado enmascarado (cursor variable para Java) ------------------
  v_cnt1 := 0;
  v_cnt2 := 0;
  v_rc := pkg_cpl_mgmt.list_complaints;
  LOOP
    FETCH v_rc INTO l_id, l_sector, l_modality, l_date, l_status, l_rep_name,
                    l_rep_doc, l_cur, l_amt, l_pen, l_addr, l_lat, l_lon;
    EXIT WHEN v_rc%NOTFOUND;
    IF l_rep_name LIKE '%RESERVADA%' THEN
      v_cnt1 := v_cnt1 + 1;
      IF l_rep_doc <> '********' THEN v_cnt2 := v_cnt2 + 1; END IF;
    END IF;
  END LOOP;
  CLOSE v_rc;
  check_true(v_cnt1 > 0 AND v_cnt2 = 0,
             'T16 Listado: ' || v_cnt1 || ' anonimas mostradas sin nombre ni documento');

  DBMS_OUTPUT.PUT_LINE('============================================');
  DBMS_OUTPUT.PUT_LINE('Resultado: ' || v_ok || ' OK, ' || v_ko || ' FALLA(S)');

  -- Las pruebas no deben dejar rastro en los datos cargados
  ROLLBACK;
EXCEPTION
  WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE('[ERROR INESPERADO] ' || SQLERRM);
    DBMS_OUTPUT.PUT_LINE(DBMS_UTILITY.FORMAT_ERROR_BACKTRACE);
    ROLLBACK;
END;
/


-- =====================================================================
-- PARTE B: REPORTES SOBRE LOS DATOS CARGADOS
-- =====================================================================
EXEC pkg_cpl_mgmt.rpt_by_sector;
EXEC pkg_cpl_mgmt.rpt_by_modality;
EXEC pkg_cpl_mgmt.rpt_by_month(2026);

-- Ejemplo con rango de fechas
EXEC pkg_cpl_mgmt.rpt_by_sector(DATE '2026-07-01', DATE '2026-09-30');

-- =============================================================================
-- SECCION 3: Pruebas de investigación, asignaciones y operativos
-- Cubre el historial inmutable, los cambios de estado, la asignación de investigadores,
-- el cierre de casos, los operativos y la consistencia global.
-- Las pruebas que requieren una denuncia en un estado concreto imprimen [SKIP] si no existe.
-- =============================================================================
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
  SELECT COUNT(*) INTO v_cnt FROM TB_STAFF_OFFICER;
  IF v_cnt < 3 THEN
    DBMS_OUTPUT.PUT_LINE('Se necesitan al menos 3 oficiales en TB_STAFF_OFFICER para correr las pruebas.');
    RETURN;
  END IF;

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
      pkg_inv_mgmt.change_status(v_cpl, 'RESUELTO', v_cip1, 'Intento de salto invalido');
    EXCEPTION WHEN OTHERS THEN v_code := SQLCODE;
    END;
    expect('T03 salto REGISTRADO -> RESUELTO rechazado', -20021, v_code);

    v_code := 0;
    BEGIN
      pkg_inv_mgmt.change_status(v_cpl, 'VALIDADO_COMISARIA', v_cip1, NULL);
    EXCEPTION WHEN OTHERS THEN v_code := SQLCODE;
    END;
    expect('T04 observaciones nulas rechazadas', -20020, v_code);

    v_code := 0;
    BEGIN
      pkg_inv_mgmt.change_status(v_cpl, 'VALIDADO_COMISARIA', v_cip1, 'corto');
    EXCEPTION WHEN OTHERS THEN v_code := SQLCODE;
    END;
    expect('T05 observaciones demasiado cortas rechazadas', -20020, v_code);

    v_code := 0;
    BEGIN
      pkg_inv_mgmt.change_status(v_cpl, 'VALIDADO_COMISARIA', v_cip1, 'Validacion de prueba automatizada');
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
      v_tmp := pkg_inv_mgmt.assign_investigator(v_cpl, v_cip2, v_cip1);
    EXCEPTION WHEN OTHERS THEN v_code := SQLCODE;
    END;
    SELECT current_status INTO v_st FROM TB_CPL_COMPLAINT WHERE complaint_id = v_cpl;
    report('T07 asignar pasa la denuncia a EN_INVESTIGACION y sube el contador',
           v_code = 0 AND v_st = 'EN_INVESTIGACION' AND active_count(v_cip2) = v_c2 + 1,
           '-> codigo ' || v_code || ', estado ' || v_st);

    v_code := 0;
    BEGIN
      INSERT INTO TB_INV_ASSIGNMENT (assignment_id, complaint_id, officer_cip, assigned_by_cip)
      VALUES (seq_inv_assignment.NEXTVAL, v_cpl, v_cip3, v_cip1);
    EXCEPTION WHEN OTHERS THEN v_code := SQLCODE;
    END;
    expect('T08 segundo titular activo rechazado (indice unico)', -1, v_code);

    v_code := 0;
    BEGIN
      v_tmp := pkg_inv_mgmt.assign_investigator(v_cpl, v_cip3, v_cip1, NULL);
    EXCEPTION WHEN OTHERS THEN v_code := SQLCODE;
    END;
    expect('T09 reasignacion sin motivo rechazada', -20033, v_code);

    v_code := 0;
    BEGIN
      v_tmp := pkg_inv_mgmt.assign_investigator(v_cpl, v_cip2, v_cip1, 'Motivo de prueba suficientemente largo');
    EXCEPTION WHEN OTHERS THEN v_code := SQLCODE;
    END;
    expect('T10 reasignar al mismo titular rechazado', -20032, v_code);

    v_code := 0;
    BEGIN
      v_tmp := pkg_inv_mgmt.assign_investigator(v_cpl, v_cip3, v_cip1, 'Reasignacion de prueba por rotacion');
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
      INSERT INTO TB_INV_ASSIGNMENT (assignment_id, complaint_id, officer_cip, assigned_by_cip)
      VALUES (seq_inv_assignment.NEXTVAL, v_cpl2, v_cip2, v_cip2);
    EXCEPTION WHEN OTHERS THEN v_code := SQLCODE;
    END;
    expect('T12 detective no puede firmar su propia asignacion (CHECK)', -2290, v_code);
  END IF;

  v_cpl2 := pick_complaint('VALIDADO_COMISARIA');
  IF v_cpl2 IS NULL THEN
    skip('T13');
  ELSE
    -- Se lleva el contador del detective al limite N (15) y se intenta otra asignacion.
    v_c2 := active_count(v_cip2);
    UPDATE TB_STAFF_OFFICER SET active_case_count = 15 WHERE officer_cip = v_cip2;
    v_code := 0;
    BEGIN
      v_tmp := pkg_inv_mgmt.assign_investigator(v_cpl2, v_cip2, v_cip1);
    EXCEPTION WHEN OTHERS THEN v_code := SQLCODE;
    END;
    UPDATE TB_STAFF_OFFICER SET active_case_count = v_c2 WHERE officer_cip = v_cip2;
    expect('T13 limite N de casos activos bloquea la asignacion', -20001, v_code);
  END IF;

  DBMS_OUTPUT.PUT_LINE('=== D. Cierre de caso ===');

  IF v_cpl IS NULL THEN
    skip('T14-T15');
  ELSE
    v_c3 := active_count(v_cip3);
    v_code := 0;
    BEGIN
      pkg_inv_mgmt.change_status(v_cpl, 'ARCHIVADO', v_cip3, 'Archivo de prueba por falta de elementos');
    EXCEPTION WHEN OTHERS THEN v_code := SQLCODE;
    END;
    SELECT COUNT(*) INTO v_cnt FROM TB_INV_ASSIGNMENT WHERE complaint_id = v_cpl AND end_date IS NULL;
    report('T14 archivar cierra la asignacion y libera el cupo',
           v_code = 0 AND v_cnt = 0 AND active_count(v_cip3) = v_c3 - 1,
           '-> codigo ' || v_code || ', activas ' || v_cnt);

    v_code := 0;
    BEGIN
      pkg_inv_mgmt.change_status(v_cpl, 'EN_INVESTIGACION', v_cip1, 'Intento de reabrir un caso archivado');
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
      v_op := pkg_inv_mgmt.register_operation(v_sec, v_cip1, 'Prueba', SYSTIMESTAMP,
                pkg_inv_mgmt.t_id_list(v_cpl));
    EXCEPTION WHEN OTHERS THEN v_code := SQLCODE;
    END;
    expect('T16 operativo con denuncia fuera de INTERVENCION_PROGRAMADA rechazado', -20040, v_code);

    SELECT sector_id INTO v_sec FROM TB_CPL_COMPLAINT WHERE complaint_id = v_cpl2;
    v_code := 0;
    BEGIN
      v_op := pkg_inv_mgmt.register_operation(v_sec, v_cip1, 'Prueba', SYSTIMESTAMP,
                pkg_inv_mgmt.t_id_list(v_cpl2));
    EXCEPTION WHEN OTHERS THEN v_code := SQLCODE;
    END;
    SELECT COUNT(*) INTO v_cnt FROM TB_OPS_OPERATION_COMPLAINT WHERE operation_id = v_op;
    report('T17 register_operation crea cabecera y vincula 1 denuncia',
           v_code = 0 AND v_cnt = 1,
           '-> codigo ' || v_code || ', denuncias ' || v_cnt);

    IF v_op IS NULL THEN
      skip('T18');
    ELSE
      pkg_inv_mgmt.delete_operation(v_op);
      SELECT COUNT(*) INTO v_cnt FROM TB_OPS_OPERATION_COMPLAINT WHERE operation_id = v_op;
      report('T18 borrar el operativo elimina en cascada sus relaciones',
             v_cnt = 0, '-> denuncias ' || v_cnt);
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
    FROM (SELECT complaint_id FROM TB_INV_ASSIGNMENT WHERE role_type = 'PRIMARY' AND end_date IS NULL
           GROUP BY complaint_id HAVING COUNT(*) > 1);
  expect('T21 ninguna denuncia con mas de un titular activo', 0, v_cnt);

  DBMS_OUTPUT.PUT_LINE('-------------------------------------------');
  DBMS_OUTPUT.PUT_LINE('Resultado: ' || v_pass || ' PASS, ' || v_fail || ' FAIL');
  ROLLBACK;   -- las pruebas no dejan cambios
END;
/

-- Conteo de filas de las tablas de investigación y operativos.
SELECT 'TB_INV_ASSIGNMENT' AS tabla, COUNT(*) AS filas FROM TB_INV_ASSIGNMENT UNION ALL
SELECT 'TB_INV_STATUS_HISTORY',      COUNT(*) FROM TB_INV_STATUS_HISTORY UNION ALL
SELECT 'TB_OPS_OPERATION',           COUNT(*) FROM TB_OPS_OPERATION UNION ALL
SELECT 'TB_OPS_OPERATION_COMPLAINT', COUNT(*) FROM TB_OPS_OPERATION_COMPLAINT;

