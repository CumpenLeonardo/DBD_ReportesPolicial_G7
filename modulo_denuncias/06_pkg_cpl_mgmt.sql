-- =====================================================================
-- GEO-DENUNCIA | Grupo 07 | Modulo CPL (Denuncias)
-- 06_pkg_cpl_mgmt.sql : paquete PKG_CPL_MGMT
--   1. CRUD de las 6 tablas del modulo
--   2. register_complaint: registro con asignacion de sector por GPS y
--      enmascaramiento de identidad si la denuncia es anonima
--   3. Reportes en soles con cursores explicitos: por sector, por
--      modalidad y por mes
--
-- Control transaccional: el paquete NO hace COMMIT. Confirma o deshace
-- quien lo llama (script, Java, otro paquete). Las operaciones de varios
-- pasos usan SAVEPOINT para ser atomicas sin cerrar la transaccion.
--
-- Prerrequisitos: 03_cpl_ddl.sql y 04_cpl_triggers.sql ejecutados.
-- Ejecutar con F5 (Run Script) conectado como el dueno del esquema.
-- =====================================================================


-- =====================================================================
-- ESPECIFICACION (interfaz publica)
-- =====================================================================
CREATE OR REPLACE PACKAGE pkg_cpl_mgmt AS

  -- Codigos de error del modulo CPL
  --   -20101  moneda inexistente (trigger trg_cpl_complaint_pen)
  --   -20110  registro no encontrado
  --   -20111  registro con dependientes: no se puede eliminar
  --   -20112  referencia a un registro padre inexistente (FK)
  --   -20113  ningun sector contiene el punto GPS
  --   -20114  denuncia anonima sin oficial que apruebe la reserva
  --   -20115  valor duplicado (PK/UK)
  --   -20116  dato invalido (CHECK o NOT NULL)
  --   -20117  parametro invalido
  --   -20118  denuncia no editable por su estado
  --   -20199  error no previsto

  -- ---------------- MODALIDADES ----------------
  FUNCTION  ins_modality (p_name     tb_cpl_modality.modality_name%TYPE,
                          p_severity tb_cpl_modality.severity_level%TYPE)
            RETURN tb_cpl_modality.modality_id%TYPE;
  PROCEDURE upd_modality (p_modality_id tb_cpl_modality.modality_id%TYPE,
                          p_name        tb_cpl_modality.modality_name%TYPE,
                          p_severity    tb_cpl_modality.severity_level%TYPE);
  PROCEDURE del_modality (p_modality_id tb_cpl_modality.modality_id%TYPE);
  FUNCTION  get_modality (p_modality_id tb_cpl_modality.modality_id%TYPE)
            RETURN tb_cpl_modality%ROWTYPE;

  -- ---------------- ESTABLECIMIENTOS ----------------
  FUNCTION  ins_establishment (p_name      tb_cpl_establishment.establishment_name%TYPE,
                               p_type      tb_cpl_establishment.establishment_type%TYPE,
                               p_address   tb_cpl_establishment.address%TYPE,
                               p_latitude  tb_cpl_establishment.latitude%TYPE,
                               p_longitude tb_cpl_establishment.longitude%TYPE)
            RETURN tb_cpl_establishment.establishment_id%TYPE;
  PROCEDURE upd_establishment (p_establishment_id tb_cpl_establishment.establishment_id%TYPE,
                               p_name      tb_cpl_establishment.establishment_name%TYPE,
                               p_type      tb_cpl_establishment.establishment_type%TYPE,
                               p_address   tb_cpl_establishment.address%TYPE,
                               p_latitude  tb_cpl_establishment.latitude%TYPE,
                               p_longitude tb_cpl_establishment.longitude%TYPE);
  PROCEDURE del_establishment (p_establishment_id tb_cpl_establishment.establishment_id%TYPE);
  FUNCTION  get_establishment (p_establishment_id tb_cpl_establishment.establishment_id%TYPE)
            RETURN tb_cpl_establishment%ROWTYPE;

  -- ---------------- DENUNCIANTES ----------------
  FUNCTION  ins_reporter (p_document_id tb_cpl_reporter.personal_document_id%TYPE,
                          p_first_name  tb_cpl_reporter.first_name%TYPE,
                          p_last_name   tb_cpl_reporter.last_name%TYPE,
                          p_gender      tb_cpl_reporter.gender%TYPE,
                          p_address     tb_cpl_reporter.address%TYPE,
                          p_phone       tb_cpl_reporter.phone_number%TYPE,
                          p_email       tb_cpl_reporter.email%TYPE DEFAULT NULL)
            RETURN tb_cpl_reporter.id_reporter%TYPE;
  PROCEDURE upd_reporter (p_id_reporter tb_cpl_reporter.id_reporter%TYPE,
                          p_first_name  tb_cpl_reporter.first_name%TYPE,
                          p_last_name   tb_cpl_reporter.last_name%TYPE,
                          p_gender      tb_cpl_reporter.gender%TYPE,
                          p_address     tb_cpl_reporter.address%TYPE,
                          p_phone       tb_cpl_reporter.phone_number%TYPE,
                          p_email       tb_cpl_reporter.email%TYPE DEFAULT NULL);
  PROCEDURE del_reporter (p_id_reporter tb_cpl_reporter.id_reporter%TYPE);
  FUNCTION  get_reporter (p_id_reporter tb_cpl_reporter.id_reporter%TYPE)
            RETURN tb_cpl_reporter%ROWTYPE;

  -- ---------------- PROTECCIONES (codigo protegido) ----------------
  FUNCTION  ins_protection (p_id_reporter tb_cpl_complaint_protection.id_reporter%TYPE,
                            p_officer_cip tb_cpl_complaint_protection.approved_by_officer%TYPE)
            RETURN tb_cpl_complaint_protection.protected_code%TYPE;
  PROCEDURE upd_protection (p_protected_code tb_cpl_complaint_protection.protected_code%TYPE,
                            p_officer_cip    tb_cpl_complaint_protection.approved_by_officer%TYPE);
  PROCEDURE del_protection (p_protected_code tb_cpl_complaint_protection.protected_code%TYPE);
  FUNCTION  get_protection (p_protected_code tb_cpl_complaint_protection.protected_code%TYPE)
            RETURN tb_cpl_complaint_protection%ROWTYPE;

  -- ---------------- DENUNCIAS ----------------
  -- Sector cuyo rectangulo (min/max lat/lon) contiene el punto GPS
  FUNCTION  find_sector (p_latitude  tb_cpl_complaint.latitude%TYPE,
                         p_longitude tb_cpl_complaint.longitude%TYPE)
            RETURN tb_cpl_complaint.sector_id%TYPE;

  -- Alta de denuncia. Si p_is_anonymous = 'Y', la identidad se guarda solo
  -- en TB_CPL_COMPLAINT_PROTECTION y la denuncia recibe el codigo protegido.
  FUNCTION  register_complaint (
              p_is_anonymous       tb_cpl_complaint.is_anonymous%TYPE,
              p_document_id        tb_cpl_reporter.personal_document_id%TYPE,
              p_first_name         tb_cpl_reporter.first_name%TYPE,
              p_last_name          tb_cpl_reporter.last_name%TYPE,
              p_gender             tb_cpl_reporter.gender%TYPE,
              p_address            tb_cpl_reporter.address%TYPE,
              p_phone              tb_cpl_reporter.phone_number%TYPE,
              p_modality_id        tb_cpl_complaint.modality_id%TYPE,
              p_incident_date      tb_cpl_complaint.incident_date%TYPE,
              p_latitude           tb_cpl_complaint.latitude%TYPE,
              p_longitude          tb_cpl_complaint.longitude%TYPE,
              p_incident_address   tb_cpl_complaint.incident_address%TYPE,
              p_email              tb_cpl_reporter.email%TYPE                    DEFAULT NULL,
              p_currency_id        tb_cpl_complaint.currency_id%TYPE             DEFAULT 1,
              p_amount_original    tb_cpl_complaint.amount_original%TYPE         DEFAULT 0,
              p_payment_frequency  tb_cpl_complaint.payment_frequency%TYPE       DEFAULT NULL,
              p_extortionist_alias tb_cpl_complaint.extortionist_alias%TYPE      DEFAULT NULL,
              p_establishment_id   tb_cpl_complaint.establishment_id%TYPE        DEFAULT NULL,
              p_assoc_id           tb_cpl_complaint.assoc_id%TYPE                DEFAULT NULL,
              p_officer_cip        tb_cpl_complaint_protection.approved_by_officer%TYPE DEFAULT NULL)
            RETURN tb_cpl_complaint.complaint_id%TYPE;

  -- Edicion de datos del hecho (solo en estado REGISTRADO)
  PROCEDURE upd_complaint (
              p_complaint_id       tb_cpl_complaint.complaint_id%TYPE,
              p_modality_id        tb_cpl_complaint.modality_id%TYPE,
              p_currency_id        tb_cpl_complaint.currency_id%TYPE,
              p_amount_original    tb_cpl_complaint.amount_original%TYPE,
              p_payment_frequency  tb_cpl_complaint.payment_frequency%TYPE,
              p_extortionist_alias tb_cpl_complaint.extortionist_alias%TYPE,
              p_establishment_id   tb_cpl_complaint.establishment_id%TYPE,
              p_assoc_id           tb_cpl_complaint.assoc_id%TYPE);

  -- Cambio de ubicacion: recalcula el sector (solo en estado REGISTRADO)
  PROCEDURE upd_complaint_location (
              p_complaint_id     tb_cpl_complaint.complaint_id%TYPE,
              p_latitude         tb_cpl_complaint.latitude%TYPE,
              p_longitude        tb_cpl_complaint.longitude%TYPE,
              p_incident_address tb_cpl_complaint.incident_address%TYPE);

  -- Baja (solo en estado REGISTRADO): elimina evidencias y proteccion
  PROCEDURE del_complaint (p_complaint_id tb_cpl_complaint.complaint_id%TYPE);

  FUNCTION  get_complaint (p_complaint_id tb_cpl_complaint.complaint_id%TYPE)
            RETURN tb_cpl_complaint%ROWTYPE;

  -- Nombre del denunciante para mostrar: enmascarado si es anonima
  FUNCTION  reporter_display (p_complaint_id tb_cpl_complaint.complaint_id%TYPE)
            RETURN VARCHAR2;

  -- Listado enmascarado para la aplicacion (Java): cursor variable
  FUNCTION  list_complaints (p_sector_id tb_cpl_complaint.sector_id%TYPE DEFAULT NULL)
            RETURN SYS_REFCURSOR;

  -- ---------------- EVIDENCIAS ----------------
  FUNCTION  ins_evidence (p_complaint_id tb_cpl_digital_evidence.complaint_id%TYPE,
                          p_uploaded_by  tb_cpl_digital_evidence.uploaded_by_cip%TYPE,
                          p_type         tb_cpl_digital_evidence.evidence_type%TYPE,
                          p_file_path    tb_cpl_digital_evidence.file_path%TYPE,
                          p_description  tb_cpl_digital_evidence.description%TYPE)
            RETURN tb_cpl_digital_evidence.evidence_id%TYPE;
  PROCEDURE upd_evidence (p_evidence_id  tb_cpl_digital_evidence.evidence_id%TYPE,
                          p_type         tb_cpl_digital_evidence.evidence_type%TYPE,
                          p_file_path    tb_cpl_digital_evidence.file_path%TYPE,
                          p_description  tb_cpl_digital_evidence.description%TYPE);
  PROCEDURE del_evidence (p_evidence_id  tb_cpl_digital_evidence.evidence_id%TYPE);
  FUNCTION  get_evidence (p_evidence_id  tb_cpl_digital_evidence.evidence_id%TYPE)
            RETURN tb_cpl_digital_evidence%ROWTYPE;

  -- ---------------- REPORTES (cursores explicitos, montos en soles) ----------------
  PROCEDURE rpt_by_sector   (p_date_from DATE DEFAULT NULL, p_date_to DATE DEFAULT NULL);
  PROCEDURE rpt_by_modality (p_date_from DATE DEFAULT NULL, p_date_to DATE DEFAULT NULL);
  PROCEDURE rpt_by_month    (p_year NUMBER DEFAULT NULL);

END pkg_cpl_mgmt;
/


-- =====================================================================
-- CUERPO (implementacion)
-- =====================================================================
CREATE OR REPLACE PACKAGE BODY pkg_cpl_mgmt AS

  -- -------------------------------------------------------------------
  -- Cursores explicitos de los reportes (declarados a nivel de paquete).
  -- El filtro de fechas va en el ON del LEFT JOIN: si fuera en el WHERE,
  -- los sectores o modalidades sin denuncias desaparecerian del reporte.
  -- -------------------------------------------------------------------
  CURSOR c_rpt_sector (cp_from DATE, cp_to DATE) IS
    SELECT s.sector_id,
           s.sector_name,
           COUNT(c.complaint_id)                              AS total_cases,
           SUM(CASE WHEN c.is_anonymous = 'Y' THEN 1 ELSE 0 END) AS anon_cases,
           NVL(SUM(c.amount_pen), 0)                          AS total_pen,
           NVL(ROUND(AVG(c.amount_pen), 2), 0)                AS avg_pen,
           NVL(MAX(c.amount_pen), 0)                          AS max_pen
      FROM tb_terr_sector s
      LEFT JOIN tb_cpl_complaint c
        ON c.sector_id      = s.sector_id
       AND c.incident_date >= NVL(cp_from, DATE '1900-01-01')
       AND c.incident_date <  NVL(cp_to + 1, DATE '9999-12-31')
     GROUP BY s.sector_id, s.sector_name
     ORDER BY total_pen DESC, s.sector_id;

  CURSOR c_rpt_modality (cp_from DATE, cp_to DATE) IS
    SELECT m.modality_id,
           m.modality_name,
           m.severity_level,
           COUNT(c.complaint_id)                AS total_cases,
           NVL(SUM(c.amount_pen), 0)            AS total_pen,
           NVL(ROUND(AVG(c.amount_pen), 2), 0)  AS avg_pen
      FROM tb_cpl_modality m
      LEFT JOIN tb_cpl_complaint c
        ON c.modality_id    = m.modality_id
       AND c.incident_date >= NVL(cp_from, DATE '1900-01-01')
       AND c.incident_date <  NVL(cp_to + 1, DATE '9999-12-31')
     GROUP BY m.modality_id, m.modality_name, m.severity_level
     ORDER BY total_pen DESC, m.modality_id;

  CURSOR c_rpt_month (cp_year NUMBER) IS
    SELECT TO_CHAR(c.incident_date, 'YYYY-MM')                    AS month_key,
           COUNT(*)                                               AS total_cases,
           SUM(CASE WHEN cu.currency_code = 'PEN' THEN 1 ELSE 0 END) AS pen_cases,
           SUM(CASE WHEN cu.currency_code = 'USD' THEN 1 ELSE 0 END) AS usd_cases,
           SUM(CASE WHEN cu.currency_code = 'EUR' THEN 1 ELSE 0 END) AS eur_cases,
           SUM(c.amount_pen)                                      AS total_pen
      FROM tb_cpl_complaint c
      JOIN tb_cfg_currency  cu ON cu.currency_id = c.currency_id
     WHERE cp_year IS NULL
        OR EXTRACT(YEAR FROM c.incident_date) = cp_year
     GROUP BY TO_CHAR(c.incident_date, 'YYYY-MM')
     ORDER BY month_key;


  -- ===================================================================
  -- SUBPROGRAMAS PRIVADOS (no figuran en la especificacion)
  -- ===================================================================

  -- Traduce errores de Oracle a los codigos del modulo
  PROCEDURE raise_dml_error (p_context VARCHAR2, p_code NUMBER, p_msg VARCHAR2) IS
  BEGIN
    IF p_code BETWEEN -20999 AND -20000 THEN
      -- Error propio (del paquete o de un trigger): se propaga con su codigo
      RAISE_APPLICATION_ERROR(p_code, SUBSTR(p_msg, 12));
    ELSIF p_code = -1 THEN
      RAISE_APPLICATION_ERROR(-20115, p_context || ': valor duplicado (PK/UK). ' || p_msg);
    ELSIF p_code = -2291 THEN
      RAISE_APPLICATION_ERROR(-20112, p_context || ': referencia a un registro padre inexistente. ' || p_msg);
    ELSIF p_code = -2292 THEN
      RAISE_APPLICATION_ERROR(-20111, p_context || ': tiene registros dependientes. ' || p_msg);
    ELSIF p_code IN (-2290, -1400, -1407) THEN
      RAISE_APPLICATION_ERROR(-20116, p_context || ': dato invalido. ' || p_msg);
    ELSE
      RAISE_APPLICATION_ERROR(-20199, p_context || ': ' || p_msg);
    END IF;
  END raise_dml_error;

  -- Lanza -20110 si un UPDATE/DELETE no afecto filas
  PROCEDURE check_found (p_rows NUMBER, p_entity VARCHAR2, p_id VARCHAR2) IS
  BEGIN
    IF p_rows = 0 THEN
      RAISE_APPLICATION_ERROR(-20110, p_entity || ' ' || p_id || ' no existe.');
    END IF;
  END check_found;

  -- Formato de montos en soles
  FUNCTION fmt_pen (p_amount NUMBER) RETURN VARCHAR2 IS
  BEGIN
    RETURN 'S/ ' || TO_CHAR(NVL(p_amount, 0), 'FM9,999,999,990.00');
  END fmt_pen;

  -- Verifica que la denuncia exista y siga en REGISTRADO.
  -- FOR UPDATE bloquea la fila: nadie puede cambiar su estado entre
  -- esta verificacion y la modificacion posterior.
  PROCEDURE assert_editable (p_complaint_id tb_cpl_complaint.complaint_id%TYPE) IS
    v_status tb_cpl_complaint.current_status%TYPE;
  BEGIN
    SELECT current_status
      INTO v_status
      FROM tb_cpl_complaint
     WHERE complaint_id = p_complaint_id
       FOR UPDATE;

    IF v_status <> 'REGISTRADO' THEN
      RAISE_APPLICATION_ERROR(-20118, 'La denuncia ' || p_complaint_id ||
        ' esta en estado ' || v_status || ' y ya no puede modificarse.');
    END IF;
  EXCEPTION
    WHEN NO_DATA_FOUND THEN
      RAISE_APPLICATION_ERROR(-20110, 'Denuncia ' || p_complaint_id || ' no existe.');
  END assert_editable;


  -- ===================================================================
  -- MODALIDADES
  -- ===================================================================
  FUNCTION ins_modality (p_name     tb_cpl_modality.modality_name%TYPE,
                         p_severity tb_cpl_modality.severity_level%TYPE)
    RETURN tb_cpl_modality.modality_id%TYPE IS
    v_id tb_cpl_modality.modality_id%TYPE;
  BEGIN
    INSERT INTO tb_cpl_modality (modality_id, modality_name, severity_level)
    VALUES (seq_cpl_modality.NEXTVAL, p_name, p_severity)
    RETURNING modality_id INTO v_id;
    RETURN v_id;
  EXCEPTION
    WHEN OTHERS THEN raise_dml_error('ins_modality', SQLCODE, SQLERRM);
  END ins_modality;

  PROCEDURE upd_modality (p_modality_id tb_cpl_modality.modality_id%TYPE,
                          p_name        tb_cpl_modality.modality_name%TYPE,
                          p_severity    tb_cpl_modality.severity_level%TYPE) IS
    v_rows PLS_INTEGER;
  BEGIN
    BEGIN
      UPDATE tb_cpl_modality
         SET modality_name  = p_name,
             severity_level = p_severity
       WHERE modality_id = p_modality_id;
      v_rows := SQL%ROWCOUNT;
    EXCEPTION
      WHEN OTHERS THEN raise_dml_error('upd_modality', SQLCODE, SQLERRM);
    END;
    check_found(v_rows, 'Modalidad', p_modality_id);
  END upd_modality;

  PROCEDURE del_modality (p_modality_id tb_cpl_modality.modality_id%TYPE) IS
    v_rows PLS_INTEGER;
  BEGIN
    BEGIN
      DELETE FROM tb_cpl_modality WHERE modality_id = p_modality_id;
      v_rows := SQL%ROWCOUNT;
    EXCEPTION
      WHEN OTHERS THEN raise_dml_error('del_modality', SQLCODE, SQLERRM);
    END;
    check_found(v_rows, 'Modalidad', p_modality_id);
  END del_modality;

  FUNCTION get_modality (p_modality_id tb_cpl_modality.modality_id%TYPE)
    RETURN tb_cpl_modality%ROWTYPE IS
    v_row tb_cpl_modality%ROWTYPE;
  BEGIN
    SELECT * INTO v_row FROM tb_cpl_modality WHERE modality_id = p_modality_id;
    RETURN v_row;
  EXCEPTION
    WHEN NO_DATA_FOUND THEN
      RAISE_APPLICATION_ERROR(-20110, 'Modalidad ' || p_modality_id || ' no existe.');
  END get_modality;


  -- ===================================================================
  -- ESTABLECIMIENTOS (el trigger genera location_geom)
  -- ===================================================================
  FUNCTION ins_establishment (p_name      tb_cpl_establishment.establishment_name%TYPE,
                              p_type      tb_cpl_establishment.establishment_type%TYPE,
                              p_address   tb_cpl_establishment.address%TYPE,
                              p_latitude  tb_cpl_establishment.latitude%TYPE,
                              p_longitude tb_cpl_establishment.longitude%TYPE)
    RETURN tb_cpl_establishment.establishment_id%TYPE IS
    v_id tb_cpl_establishment.establishment_id%TYPE;
  BEGIN
    INSERT INTO tb_cpl_establishment
           (establishment_id, establishment_name, establishment_type,
            address, latitude, longitude)
    VALUES (seq_cpl_establishment.NEXTVAL, p_name, p_type,
            p_address, p_latitude, p_longitude)
    RETURNING establishment_id INTO v_id;
    RETURN v_id;
  EXCEPTION
    WHEN OTHERS THEN raise_dml_error('ins_establishment', SQLCODE, SQLERRM);
  END ins_establishment;

  PROCEDURE upd_establishment (p_establishment_id tb_cpl_establishment.establishment_id%TYPE,
                               p_name      tb_cpl_establishment.establishment_name%TYPE,
                               p_type      tb_cpl_establishment.establishment_type%TYPE,
                               p_address   tb_cpl_establishment.address%TYPE,
                               p_latitude  tb_cpl_establishment.latitude%TYPE,
                               p_longitude tb_cpl_establishment.longitude%TYPE) IS
    v_rows PLS_INTEGER;
  BEGIN
    BEGIN
      UPDATE tb_cpl_establishment
         SET establishment_name = p_name,
             establishment_type = p_type,
             address            = p_address,
             latitude           = p_latitude,
             longitude          = p_longitude
       WHERE establishment_id = p_establishment_id;
      v_rows := SQL%ROWCOUNT;
    EXCEPTION
      WHEN OTHERS THEN raise_dml_error('upd_establishment', SQLCODE, SQLERRM);
    END;
    check_found(v_rows, 'Establecimiento', p_establishment_id);
  END upd_establishment;

  PROCEDURE del_establishment (p_establishment_id tb_cpl_establishment.establishment_id%TYPE) IS
    v_rows PLS_INTEGER;
  BEGIN
    BEGIN
      DELETE FROM tb_cpl_establishment WHERE establishment_id = p_establishment_id;
      v_rows := SQL%ROWCOUNT;
    EXCEPTION
      WHEN OTHERS THEN raise_dml_error('del_establishment', SQLCODE, SQLERRM);
    END;
    check_found(v_rows, 'Establecimiento', p_establishment_id);
  END del_establishment;

  FUNCTION get_establishment (p_establishment_id tb_cpl_establishment.establishment_id%TYPE)
    RETURN tb_cpl_establishment%ROWTYPE IS
    v_row tb_cpl_establishment%ROWTYPE;
  BEGIN
    SELECT * INTO v_row FROM tb_cpl_establishment
     WHERE establishment_id = p_establishment_id;
    RETURN v_row;
  EXCEPTION
    WHEN NO_DATA_FOUND THEN
      RAISE_APPLICATION_ERROR(-20110, 'Establecimiento ' || p_establishment_id || ' no existe.');
  END get_establishment;


  -- ===================================================================
  -- DENUNCIANTES
  -- ===================================================================
  FUNCTION ins_reporter (p_document_id tb_cpl_reporter.personal_document_id%TYPE,
                         p_first_name  tb_cpl_reporter.first_name%TYPE,
                         p_last_name   tb_cpl_reporter.last_name%TYPE,
                         p_gender      tb_cpl_reporter.gender%TYPE,
                         p_address     tb_cpl_reporter.address%TYPE,
                         p_phone       tb_cpl_reporter.phone_number%TYPE,
                         p_email       tb_cpl_reporter.email%TYPE DEFAULT NULL)
    RETURN tb_cpl_reporter.id_reporter%TYPE IS
    v_id tb_cpl_reporter.id_reporter%TYPE;
  BEGIN
    INSERT INTO tb_cpl_reporter
           (id_reporter, personal_document_id, first_name, last_name,
            gender, address, phone_number, email)
    VALUES (seq_cpl_reporter.NEXTVAL, p_document_id, p_first_name, p_last_name,
            p_gender, p_address, p_phone, p_email)
    RETURNING id_reporter INTO v_id;
    RETURN v_id;
  EXCEPTION
    WHEN OTHERS THEN raise_dml_error('ins_reporter', SQLCODE, SQLERRM);
  END ins_reporter;

  PROCEDURE upd_reporter (p_id_reporter tb_cpl_reporter.id_reporter%TYPE,
                          p_first_name  tb_cpl_reporter.first_name%TYPE,
                          p_last_name   tb_cpl_reporter.last_name%TYPE,
                          p_gender      tb_cpl_reporter.gender%TYPE,
                          p_address     tb_cpl_reporter.address%TYPE,
                          p_phone       tb_cpl_reporter.phone_number%TYPE,
                          p_email       tb_cpl_reporter.email%TYPE DEFAULT NULL) IS
    v_rows PLS_INTEGER;
  BEGIN
    BEGIN
      UPDATE tb_cpl_reporter
         SET first_name   = p_first_name,
             last_name    = p_last_name,
             gender       = p_gender,
             address      = p_address,
             phone_number = p_phone,
             email        = p_email
       WHERE id_reporter = p_id_reporter;
      v_rows := SQL%ROWCOUNT;
    EXCEPTION
      WHEN OTHERS THEN raise_dml_error('upd_reporter', SQLCODE, SQLERRM);
    END;
    check_found(v_rows, 'Denunciante', p_id_reporter);
  END upd_reporter;

  PROCEDURE del_reporter (p_id_reporter tb_cpl_reporter.id_reporter%TYPE) IS
    v_rows PLS_INTEGER;
  BEGIN
    BEGIN
      DELETE FROM tb_cpl_reporter WHERE id_reporter = p_id_reporter;
      v_rows := SQL%ROWCOUNT;
    EXCEPTION
      WHEN OTHERS THEN raise_dml_error('del_reporter', SQLCODE, SQLERRM);
    END;
    check_found(v_rows, 'Denunciante', p_id_reporter);
  END del_reporter;

  FUNCTION get_reporter (p_id_reporter tb_cpl_reporter.id_reporter%TYPE)
    RETURN tb_cpl_reporter%ROWTYPE IS
    v_row tb_cpl_reporter%ROWTYPE;
  BEGIN
    SELECT * INTO v_row FROM tb_cpl_reporter WHERE id_reporter = p_id_reporter;
    RETURN v_row;
  EXCEPTION
    WHEN NO_DATA_FOUND THEN
      RAISE_APPLICATION_ERROR(-20110, 'Denunciante ' || p_id_reporter || ' no existe.');
  END get_reporter;


  -- ===================================================================
  -- PROTECCIONES
  -- ===================================================================
  FUNCTION ins_protection (p_id_reporter tb_cpl_complaint_protection.id_reporter%TYPE,
                           p_officer_cip tb_cpl_complaint_protection.approved_by_officer%TYPE)
    RETURN tb_cpl_complaint_protection.protected_code%TYPE IS
    v_code tb_cpl_complaint_protection.protected_code%TYPE;
  BEGIN
    INSERT INTO tb_cpl_complaint_protection
           (protected_code, id_reporter, approved_by_officer)
    VALUES (seq_cpl_protection.NEXTVAL, p_id_reporter, p_officer_cip)
    RETURNING protected_code INTO v_code;
    RETURN v_code;
  EXCEPTION
    WHEN OTHERS THEN raise_dml_error('ins_protection', SQLCODE, SQLERRM);
  END ins_protection;

  PROCEDURE upd_protection (p_protected_code tb_cpl_complaint_protection.protected_code%TYPE,
                            p_officer_cip    tb_cpl_complaint_protection.approved_by_officer%TYPE) IS
    v_rows PLS_INTEGER;
  BEGIN
    BEGIN
      UPDATE tb_cpl_complaint_protection
         SET approved_by_officer = p_officer_cip,
             date_approved       = SYSTIMESTAMP
       WHERE protected_code = p_protected_code;
      v_rows := SQL%ROWCOUNT;
    EXCEPTION
      WHEN OTHERS THEN raise_dml_error('upd_protection', SQLCODE, SQLERRM);
    END;
    check_found(v_rows, 'Proteccion', p_protected_code);
  END upd_protection;

  PROCEDURE del_protection (p_protected_code tb_cpl_complaint_protection.protected_code%TYPE) IS
    v_rows PLS_INTEGER;
  BEGIN
    BEGIN
      DELETE FROM tb_cpl_complaint_protection WHERE protected_code = p_protected_code;
      v_rows := SQL%ROWCOUNT;
    EXCEPTION
      WHEN OTHERS THEN raise_dml_error('del_protection', SQLCODE, SQLERRM);
    END;
    check_found(v_rows, 'Proteccion', p_protected_code);
  END del_protection;

  FUNCTION get_protection (p_protected_code tb_cpl_complaint_protection.protected_code%TYPE)
    RETURN tb_cpl_complaint_protection%ROWTYPE IS
    v_row tb_cpl_complaint_protection%ROWTYPE;
  BEGIN
    SELECT * INTO v_row FROM tb_cpl_complaint_protection
     WHERE protected_code = p_protected_code;
    RETURN v_row;
  EXCEPTION
    WHEN NO_DATA_FOUND THEN
      RAISE_APPLICATION_ERROR(-20110, 'Proteccion ' || p_protected_code || ' no existe.');
  END get_protection;


  -- ===================================================================
  -- DENUNCIAS
  -- ===================================================================
  FUNCTION find_sector (p_latitude  tb_cpl_complaint.latitude%TYPE,
                        p_longitude tb_cpl_complaint.longitude%TYPE)
    RETURN tb_cpl_complaint.sector_id%TYPE IS
    v_sector tb_cpl_complaint.sector_id%TYPE;
  BEGIN
    SELECT sector_id
      INTO v_sector
      FROM (SELECT sector_id
              FROM tb_terr_sector
             WHERE p_latitude  BETWEEN min_lat AND max_lat
               AND p_longitude BETWEEN min_lon AND max_lon
             ORDER BY sector_id)
     WHERE ROWNUM = 1;
    RETURN v_sector;
  EXCEPTION
    WHEN NO_DATA_FOUND THEN
      RAISE_APPLICATION_ERROR(-20113, 'Ningun sector contiene el punto (' ||
        p_latitude || ', ' || p_longitude || ').');
  END find_sector;

  FUNCTION register_complaint (
             p_is_anonymous       tb_cpl_complaint.is_anonymous%TYPE,
             p_document_id        tb_cpl_reporter.personal_document_id%TYPE,
             p_first_name         tb_cpl_reporter.first_name%TYPE,
             p_last_name          tb_cpl_reporter.last_name%TYPE,
             p_gender             tb_cpl_reporter.gender%TYPE,
             p_address            tb_cpl_reporter.address%TYPE,
             p_phone              tb_cpl_reporter.phone_number%TYPE,
             p_modality_id        tb_cpl_complaint.modality_id%TYPE,
             p_incident_date      tb_cpl_complaint.incident_date%TYPE,
             p_latitude           tb_cpl_complaint.latitude%TYPE,
             p_longitude          tb_cpl_complaint.longitude%TYPE,
             p_incident_address   tb_cpl_complaint.incident_address%TYPE,
             p_email              tb_cpl_reporter.email%TYPE                    DEFAULT NULL,
             p_currency_id        tb_cpl_complaint.currency_id%TYPE             DEFAULT 1,
             p_amount_original    tb_cpl_complaint.amount_original%TYPE         DEFAULT 0,
             p_payment_frequency  tb_cpl_complaint.payment_frequency%TYPE       DEFAULT NULL,
             p_extortionist_alias tb_cpl_complaint.extortionist_alias%TYPE      DEFAULT NULL,
             p_establishment_id   tb_cpl_complaint.establishment_id%TYPE        DEFAULT NULL,
             p_assoc_id           tb_cpl_complaint.assoc_id%TYPE                DEFAULT NULL,
             p_officer_cip        tb_cpl_complaint_protection.approved_by_officer%TYPE DEFAULT NULL)
    RETURN tb_cpl_complaint.complaint_id%TYPE IS

    v_sector tb_cpl_complaint.sector_id%TYPE;
    v_rep    tb_cpl_reporter.id_reporter%TYPE;
    v_prot   tb_cpl_complaint.protected_code%TYPE;
    v_id     tb_cpl_complaint.complaint_id%TYPE;
  BEGIN
    -- Punto de retorno: si algo falla, se deshacen TODOS los pasos de este
    -- registro (denunciante, proteccion, denuncia) sin tocar el resto de la
    -- transaccion del llamador.
    SAVEPOINT sp_register;

    -- 1. Validaciones de negocio
    IF p_is_anonymous IS NULL OR p_is_anonymous NOT IN ('Y', 'N') THEN
      RAISE_APPLICATION_ERROR(-20117, 'p_is_anonymous debe ser Y o N.');
    END IF;

    IF p_is_anonymous = 'Y' AND p_officer_cip IS NULL THEN
      RAISE_APPLICATION_ERROR(-20114, 'Una denuncia anonima requiere el CIP del ' ||
        'oficial que aprueba la reserva de identidad.');
    END IF;

    -- 2. Asignacion automatica del sector por GPS
    v_sector := find_sector(p_latitude, p_longitude);

    -- 3. Denunciante: se reutiliza si el documento ya esta registrado
    BEGIN
      SELECT id_reporter
        INTO v_rep
        FROM tb_cpl_reporter
       WHERE personal_document_id = p_document_id;
    EXCEPTION
      WHEN NO_DATA_FOUND THEN
        v_rep := ins_reporter(p_document_id, p_first_name, p_last_name,
                              p_gender, p_address, p_phone, p_email);
    END;

    -- 4. Enmascaramiento: en una anonima la identidad queda SOLO en la
    --    proteccion; la denuncia guarda el codigo, nunca el id del denunciante
    IF p_is_anonymous = 'Y' THEN
      v_prot := ins_protection(v_rep, p_officer_cip);
      v_rep  := NULL;
    ELSE
      v_prot := NULL;
    END IF;

    -- 5. Denuncia (los triggers completan incident_location y amount_pen)
    INSERT INTO tb_cpl_complaint
           (complaint_id, sector_id, modality_id, establishment_id, assoc_id,
            incident_date, is_anonymous, currency_id, amount_original,
            payment_frequency, extortionist_alias, latitude, longitude,
            incident_address, id_reporter, protected_code)
    VALUES (seq_cpl_complaint.NEXTVAL, v_sector, p_modality_id, p_establishment_id, p_assoc_id,
            p_incident_date, p_is_anonymous, p_currency_id, p_amount_original,
            p_payment_frequency, p_extortionist_alias, p_latitude, p_longitude,
            p_incident_address, v_rep, v_prot)
    RETURNING complaint_id INTO v_id;

    RETURN v_id;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK TO sp_register;
      raise_dml_error('register_complaint', SQLCODE, SQLERRM);
  END register_complaint;

  PROCEDURE upd_complaint (
              p_complaint_id       tb_cpl_complaint.complaint_id%TYPE,
              p_modality_id        tb_cpl_complaint.modality_id%TYPE,
              p_currency_id        tb_cpl_complaint.currency_id%TYPE,
              p_amount_original    tb_cpl_complaint.amount_original%TYPE,
              p_payment_frequency  tb_cpl_complaint.payment_frequency%TYPE,
              p_extortionist_alias tb_cpl_complaint.extortionist_alias%TYPE,
              p_establishment_id   tb_cpl_complaint.establishment_id%TYPE,
              p_assoc_id           tb_cpl_complaint.assoc_id%TYPE) IS
  BEGIN
    assert_editable(p_complaint_id);

    UPDATE tb_cpl_complaint
       SET modality_id        = p_modality_id,
           currency_id        = p_currency_id,
           amount_original    = p_amount_original,
           payment_frequency  = p_payment_frequency,
           extortionist_alias = p_extortionist_alias,
           establishment_id   = p_establishment_id,
           assoc_id           = p_assoc_id
     WHERE complaint_id = p_complaint_id;
  EXCEPTION
    WHEN OTHERS THEN raise_dml_error('upd_complaint', SQLCODE, SQLERRM);
  END upd_complaint;

  PROCEDURE upd_complaint_location (
              p_complaint_id     tb_cpl_complaint.complaint_id%TYPE,
              p_latitude         tb_cpl_complaint.latitude%TYPE,
              p_longitude        tb_cpl_complaint.longitude%TYPE,
              p_incident_address tb_cpl_complaint.incident_address%TYPE) IS
    v_sector tb_cpl_complaint.sector_id%TYPE;
  BEGIN
    assert_editable(p_complaint_id);
    v_sector := find_sector(p_latitude, p_longitude);

    UPDATE tb_cpl_complaint
       SET latitude         = p_latitude,
           longitude        = p_longitude,
           incident_address = p_incident_address,
           sector_id        = v_sector
     WHERE complaint_id = p_complaint_id;
  EXCEPTION
    WHEN OTHERS THEN raise_dml_error('upd_complaint_location', SQLCODE, SQLERRM);
  END upd_complaint_location;

  PROCEDURE del_complaint (p_complaint_id tb_cpl_complaint.complaint_id%TYPE) IS
    v_prot tb_cpl_complaint.protected_code%TYPE;
  BEGIN
    SAVEPOINT sp_del_complaint;

    assert_editable(p_complaint_id);

    SELECT protected_code INTO v_prot
      FROM tb_cpl_complaint
     WHERE complaint_id = p_complaint_id;

    -- Orden inverso a las FK: hijos primero
    DELETE FROM tb_cpl_digital_evidence WHERE complaint_id = p_complaint_id;
    DELETE FROM tb_cpl_complaint        WHERE complaint_id = p_complaint_id;

    IF v_prot IS NOT NULL THEN
      DELETE FROM tb_cpl_complaint_protection WHERE protected_code = v_prot;
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK TO sp_del_complaint;
      raise_dml_error('del_complaint', SQLCODE, SQLERRM);
  END del_complaint;

  FUNCTION get_complaint (p_complaint_id tb_cpl_complaint.complaint_id%TYPE)
    RETURN tb_cpl_complaint%ROWTYPE IS
    v_row tb_cpl_complaint%ROWTYPE;
  BEGIN
    SELECT * INTO v_row FROM tb_cpl_complaint WHERE complaint_id = p_complaint_id;
    RETURN v_row;
  EXCEPTION
    WHEN NO_DATA_FOUND THEN
      RAISE_APPLICATION_ERROR(-20110, 'Denuncia ' || p_complaint_id || ' no existe.');
  END get_complaint;

  FUNCTION reporter_display (p_complaint_id tb_cpl_complaint.complaint_id%TYPE)
    RETURN VARCHAR2 IS
    v_anon tb_cpl_complaint.is_anonymous%TYPE;
    v_prot tb_cpl_complaint.protected_code%TYPE;
    v_name VARCHAR2(110);
  BEGIN
    SELECT c.is_anonymous, c.protected_code, r.first_name || ' ' || r.last_name
      INTO v_anon, v_prot, v_name
      FROM tb_cpl_complaint c
      LEFT JOIN tb_cpl_reporter r ON r.id_reporter = c.id_reporter
     WHERE c.complaint_id = p_complaint_id;

    IF v_anon = 'Y' THEN
      RETURN '*** IDENTIDAD RESERVADA (COD. ' || v_prot || ') ***';
    END IF;
    RETURN v_name;
  EXCEPTION
    WHEN NO_DATA_FOUND THEN
      RAISE_APPLICATION_ERROR(-20110, 'Denuncia ' || p_complaint_id || ' no existe.');
  END reporter_display;

  FUNCTION list_complaints (p_sector_id tb_cpl_complaint.sector_id%TYPE DEFAULT NULL)
    RETURN SYS_REFCURSOR IS
    v_rc SYS_REFCURSOR;
  BEGIN
    OPEN v_rc FOR
      SELECT c.complaint_id,
             s.sector_name,
             m.modality_name,
             c.incident_date,
             c.current_status,
             CASE WHEN c.is_anonymous = 'Y'
                  THEN '*** IDENTIDAD RESERVADA ***'
                  ELSE r.first_name || ' ' || r.last_name
             END                                   AS reporter_name,
             CASE WHEN c.is_anonymous = 'Y'
                  THEN '********'
                  ELSE r.personal_document_id
             END                                   AS reporter_document,
             cu.currency_code,
             c.amount_original,
             c.amount_pen,
             c.incident_address,
             c.latitude,
             c.longitude
        FROM tb_cpl_complaint c
        JOIN tb_terr_sector   s  ON s.sector_id    = c.sector_id
        JOIN tb_cpl_modality  m  ON m.modality_id  = c.modality_id
        JOIN tb_cfg_currency  cu ON cu.currency_id = c.currency_id
        LEFT JOIN tb_cpl_reporter r ON r.id_reporter = c.id_reporter
       WHERE p_sector_id IS NULL OR c.sector_id = p_sector_id
       ORDER BY c.incident_date DESC;
    RETURN v_rc;
  END list_complaints;


  -- ===================================================================
  -- EVIDENCIAS
  -- ===================================================================
  FUNCTION ins_evidence (p_complaint_id tb_cpl_digital_evidence.complaint_id%TYPE,
                         p_uploaded_by  tb_cpl_digital_evidence.uploaded_by_cip%TYPE,
                         p_type         tb_cpl_digital_evidence.evidence_type%TYPE,
                         p_file_path    tb_cpl_digital_evidence.file_path%TYPE,
                         p_description  tb_cpl_digital_evidence.description%TYPE)
    RETURN tb_cpl_digital_evidence.evidence_id%TYPE IS
    v_id tb_cpl_digital_evidence.evidence_id%TYPE;
  BEGIN
    INSERT INTO tb_cpl_digital_evidence
           (evidence_id, complaint_id, uploaded_by_cip, evidence_type,
            file_path, description)
    VALUES (seq_cpl_evidence.NEXTVAL, p_complaint_id, p_uploaded_by, p_type,
            p_file_path, p_description)
    RETURNING evidence_id INTO v_id;
    RETURN v_id;
  EXCEPTION
    WHEN OTHERS THEN raise_dml_error('ins_evidence', SQLCODE, SQLERRM);
  END ins_evidence;

  PROCEDURE upd_evidence (p_evidence_id  tb_cpl_digital_evidence.evidence_id%TYPE,
                          p_type         tb_cpl_digital_evidence.evidence_type%TYPE,
                          p_file_path    tb_cpl_digital_evidence.file_path%TYPE,
                          p_description  tb_cpl_digital_evidence.description%TYPE) IS
    v_rows PLS_INTEGER;
  BEGIN
    BEGIN
      UPDATE tb_cpl_digital_evidence
         SET evidence_type = p_type,
             file_path     = p_file_path,
             description   = p_description
       WHERE evidence_id = p_evidence_id;
      v_rows := SQL%ROWCOUNT;
    EXCEPTION
      WHEN OTHERS THEN raise_dml_error('upd_evidence', SQLCODE, SQLERRM);
    END;
    check_found(v_rows, 'Evidencia', p_evidence_id);
  END upd_evidence;

  PROCEDURE del_evidence (p_evidence_id tb_cpl_digital_evidence.evidence_id%TYPE) IS
    v_rows PLS_INTEGER;
  BEGIN
    BEGIN
      DELETE FROM tb_cpl_digital_evidence WHERE evidence_id = p_evidence_id;
      v_rows := SQL%ROWCOUNT;
    EXCEPTION
      WHEN OTHERS THEN raise_dml_error('del_evidence', SQLCODE, SQLERRM);
    END;
    check_found(v_rows, 'Evidencia', p_evidence_id);
  END del_evidence;

  FUNCTION get_evidence (p_evidence_id tb_cpl_digital_evidence.evidence_id%TYPE)
    RETURN tb_cpl_digital_evidence%ROWTYPE IS
    v_row tb_cpl_digital_evidence%ROWTYPE;
  BEGIN
    SELECT * INTO v_row FROM tb_cpl_digital_evidence WHERE evidence_id = p_evidence_id;
    RETURN v_row;
  EXCEPTION
    WHEN NO_DATA_FOUND THEN
      RAISE_APPLICATION_ERROR(-20110, 'Evidencia ' || p_evidence_id || ' no existe.');
  END get_evidence;


  -- ===================================================================
  -- REPORTES (cursores explicitos: OPEN - FETCH - EXIT WHEN - CLOSE)
  -- ===================================================================
  PROCEDURE rpt_by_sector (p_date_from DATE DEFAULT NULL, p_date_to DATE DEFAULT NULL) IS
    r        c_rpt_sector%ROWTYPE;
    v_cases  PLS_INTEGER := 0;
    v_anon   PLS_INTEGER := 0;
    v_total  NUMBER      := 0;
    v_rows   PLS_INTEGER;
  BEGIN
    DBMS_OUTPUT.PUT_LINE('REPORTE DE DENUNCIAS POR SECTOR (montos en soles)');
    DBMS_OUTPUT.PUT_LINE('Periodo: ' || NVL(TO_CHAR(p_date_from, 'DD/MM/YYYY'), 'inicio') ||
                         ' al ' || NVL(TO_CHAR(p_date_to, 'DD/MM/YYYY'), 'hoy'));
    DBMS_OUTPUT.PUT_LINE(RPAD('-', 94, '-'));
    DBMS_OUTPUT.PUT_LINE(RPAD('SECTOR', 36) || LPAD('CASOS', 7) || LPAD('ANON.', 7) ||
                         LPAD('TOTAL', 16) || LPAD('PROMEDIO', 14) || LPAD('MAXIMO', 14));
    DBMS_OUTPUT.PUT_LINE(RPAD('-', 94, '-'));

    OPEN c_rpt_sector(p_date_from, p_date_to);
    LOOP
      FETCH c_rpt_sector INTO r;
      EXIT WHEN c_rpt_sector%NOTFOUND;

      DBMS_OUTPUT.PUT_LINE(RPAD(SUBSTR(r.sector_name, 1, 35), 36) ||
                           LPAD(r.total_cases, 7) || LPAD(r.anon_cases, 7) ||
                           LPAD(fmt_pen(r.total_pen), 16) ||
                           LPAD(fmt_pen(r.avg_pen), 14) ||
                           LPAD(fmt_pen(r.max_pen), 14));
      v_cases := v_cases + r.total_cases;
      v_anon  := v_anon  + r.anon_cases;
      v_total := v_total + r.total_pen;
    END LOOP;
    v_rows := c_rpt_sector%ROWCOUNT;   -- se lee ANTES de cerrar el cursor
    CLOSE c_rpt_sector;

    DBMS_OUTPUT.PUT_LINE(RPAD('-', 94, '-'));
    DBMS_OUTPUT.PUT_LINE(RPAD('TOTAL (' || v_rows || ' sectores)', 36) ||
                         LPAD(v_cases, 7) || LPAD(v_anon, 7) || LPAD(fmt_pen(v_total), 16));
    DBMS_OUTPUT.PUT_LINE('');
  EXCEPTION
    WHEN OTHERS THEN
      IF c_rpt_sector%ISOPEN THEN CLOSE c_rpt_sector; END IF;
      RAISE;
  END rpt_by_sector;

  PROCEDURE rpt_by_modality (p_date_from DATE DEFAULT NULL, p_date_to DATE DEFAULT NULL) IS
    r        c_rpt_modality%ROWTYPE;
    v_grand  NUMBER;
    v_pct    NUMBER;
    v_cases  PLS_INTEGER := 0;
  BEGIN
    -- Total general para calcular la participacion de cada modalidad
    SELECT NVL(SUM(amount_pen), 0)
      INTO v_grand
      FROM tb_cpl_complaint
     WHERE incident_date >= NVL(p_date_from, DATE '1900-01-01')
       AND incident_date <  NVL(p_date_to + 1, DATE '9999-12-31');

    DBMS_OUTPUT.PUT_LINE('REPORTE DE DENUNCIAS POR MODALIDAD (montos en soles)');
    DBMS_OUTPUT.PUT_LINE('Periodo: ' || NVL(TO_CHAR(p_date_from, 'DD/MM/YYYY'), 'inicio') ||
                         ' al ' || NVL(TO_CHAR(p_date_to, 'DD/MM/YYYY'), 'hoy'));
    DBMS_OUTPUT.PUT_LINE(RPAD('-', 90, '-'));
    DBMS_OUTPUT.PUT_LINE(RPAD('MODALIDAD', 26) || RPAD('SEVERIDAD', 11) || LPAD('CASOS', 7) ||
                         LPAD('TOTAL', 18) || LPAD('PROMEDIO', 16) || LPAD('% MONTO', 12));
    DBMS_OUTPUT.PUT_LINE(RPAD('-', 90, '-'));

    OPEN c_rpt_modality(p_date_from, p_date_to);
    LOOP
      FETCH c_rpt_modality INTO r;
      EXIT WHEN c_rpt_modality%NOTFOUND;

      v_pct := CASE WHEN v_grand > 0 THEN ROUND(100 * r.total_pen / v_grand, 1) ELSE 0 END;

      DBMS_OUTPUT.PUT_LINE(RPAD(SUBSTR(r.modality_name, 1, 25), 26) ||
                           RPAD(r.severity_level, 11) ||
                           LPAD(r.total_cases, 7) ||
                           LPAD(fmt_pen(r.total_pen), 18) ||
                           LPAD(fmt_pen(r.avg_pen), 16) ||
                           LPAD(TO_CHAR(v_pct, 'FM990.0') || '%', 12));
      v_cases := v_cases + r.total_cases;
    END LOOP;
    CLOSE c_rpt_modality;

    DBMS_OUTPUT.PUT_LINE(RPAD('-', 90, '-'));
    DBMS_OUTPUT.PUT_LINE(RPAD('TOTAL', 37) || LPAD(v_cases, 7) || LPAD(fmt_pen(v_grand), 18));
    DBMS_OUTPUT.PUT_LINE('');
  EXCEPTION
    WHEN OTHERS THEN
      IF c_rpt_modality%ISOPEN THEN CLOSE c_rpt_modality; END IF;
      RAISE;
  END rpt_by_modality;

  PROCEDURE rpt_by_month (p_year NUMBER DEFAULT NULL) IS
    r        c_rpt_month%ROWTYPE;
    v_cases  PLS_INTEGER := 0;
    v_total  NUMBER      := 0;
  BEGIN
    DBMS_OUTPUT.PUT_LINE('REPORTE MENSUAL DE DENUNCIAS (montos en soles)');
    DBMS_OUTPUT.PUT_LINE('Anio: ' || NVL(TO_CHAR(p_year), 'todos'));
    DBMS_OUTPUT.PUT_LINE(RPAD('-', 58, '-'));
    DBMS_OUTPUT.PUT_LINE(RPAD('MES', 10) || LPAD('CASOS', 7) || LPAD('PEN', 6) ||
                         LPAD('USD', 6) || LPAD('EUR', 6) || LPAD('TOTAL EN SOLES', 23));
    DBMS_OUTPUT.PUT_LINE(RPAD('-', 58, '-'));

    OPEN c_rpt_month(p_year);
    LOOP
      FETCH c_rpt_month INTO r;
      EXIT WHEN c_rpt_month%NOTFOUND;

      DBMS_OUTPUT.PUT_LINE(RPAD(r.month_key, 10) || LPAD(r.total_cases, 7) ||
                           LPAD(r.pen_cases, 6) || LPAD(r.usd_cases, 6) ||
                           LPAD(r.eur_cases, 6) || LPAD(fmt_pen(r.total_pen), 23));
      v_cases := v_cases + r.total_cases;
      v_total := v_total + r.total_pen;
    END LOOP;

    IF c_rpt_month%ROWCOUNT = 0 THEN
      DBMS_OUTPUT.PUT_LINE('Sin denuncias para el periodo indicado.');
    END IF;
    CLOSE c_rpt_month;

    DBMS_OUTPUT.PUT_LINE(RPAD('-', 58, '-'));
    DBMS_OUTPUT.PUT_LINE(RPAD('TOTAL', 10) || LPAD(v_cases, 7) || LPAD(fmt_pen(v_total), 41));
    DBMS_OUTPUT.PUT_LINE('');
  EXCEPTION
    WHEN OTHERS THEN
      IF c_rpt_month%ISOPEN THEN CLOSE c_rpt_month; END IF;
      RAISE;
  END rpt_by_month;

END pkg_cpl_mgmt;
/


-- ---------------------------------------------------------------------
-- VERIFICACION DE COMPILACION (ambas consultas: VALID y sin errores)
-- ---------------------------------------------------------------------
SELECT object_name, object_type, status
  FROM user_objects
 WHERE object_name = 'PKG_CPL_MGMT';

SELECT name, type, line, position, text
  FROM user_errors
 WHERE name = 'PKG_CPL_MGMT'
 ORDER BY type, line;
