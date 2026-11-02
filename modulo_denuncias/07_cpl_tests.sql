-- =====================================================================
-- GEO-DENUNCIA | Grupo 07 | Modulo CPL (Denuncias)
-- 07_cpl_tests.sql : pruebas automatizadas de PKG_CPL_MGMT
--   Parte A: casos validos y casos que DEBEN fallar (se deshacen al final)
--   Parte B: los 3 reportes sobre los datos cargados
--
-- Cada prueba imprime [OK] o [FALLA]. Las pruebas no dependen de valores
-- concretos de sectores u oficiales: los leen de las tablas.
-- Ejecutar con F5 (Run Script) despues de 05_cpl_data.sql y 06_pkg_cpl_mgmt.sql.
-- =====================================================================

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

  DBMS_OUTPUT.PUT_LINE('=========== PRUEBAS PKG_CPL_MGMT ===========');

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
                p_payment_frequency => 'WEEKLY');
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
  pkg_cpl_mgmt.upd_complaint(v_id_ord, v_mod, 3, 400, 'MONTHLY', 'Los Pulpos', NULL, NULL);
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
   WHERE complaint_id = v_id_ord;    -- simula la transicion que hara el modulo de John
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
  v_ev := pkg_cpl_mgmt.ins_evidence(v_id_anon, v_cip, 'PHOTO',
                                    '/evidencias/prueba.jpg', 'Foto de prueba');
  pkg_cpl_mgmt.upd_evidence(v_ev, 'CHAT_SCREENSHOT', '/evidencias/prueba.png',
                            'Captura de prueba');
  v_evrow := pkg_cpl_mgmt.get_evidence(v_ev);
  check_true(v_evrow.evidence_type = 'CHAT_SCREENSHOT',
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
