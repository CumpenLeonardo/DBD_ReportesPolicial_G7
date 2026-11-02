-- =====================================================================
-- GEO-DENUNCIA | Grupo 07 | Modulo CPL (Denuncias)
-- 05_cpl_data.sql : carga de datos del modulo de Denuncias
--   - 5 modalidades (catalogo fijo)
--   - 12 establecimientos (coordenadas dentro de los sectores existentes)
--   - 40 denunciantes
--   - 80 denuncias (aprox. 30% anonimas, 3 monedas) + sus protecciones
--   - 0 a 3 evidencias por denuncia
--
-- Prerrequisitos:
--   * 03_cpl_ddl.sql y 04_cpl_triggers.sql ejecutados.
--   * Datos de Leonardo cargados: TB_CFG_CURRENCY (1=PEN, 2=USD, 3=EUR),
--     TB_TERR_SECTOR (con min/max lat/lon) y TB_STAFF_OFFICER.
--   * TB_COM_NEIGHBORHOOD_ASSOC de John (puede estar vacia).
--
-- Las coordenadas se generan DENTRO del rectangulo de cada sector, por lo
-- que el script funciona con los sectores reales de Leonardo sin cambios.
-- DBMS_RANDOM.SEED fija la semilla: cada ejecucion produce los mismos datos.
--
-- Ejecutar con F5 (Run Script) conectado como el dueno del esquema.
-- =====================================================================

SET SERVEROUTPUT ON


-- ---------------------------------------------------------------------
-- 0. LIMPIEZA DE DATOS PREVIOS DEL MODULO (orden inverso a las FK)
--    Solo para desarrollo: cuando existan filas de John que referencien
--    denuncias (asignaciones, historial, operativos) este DELETE fallara.
-- ---------------------------------------------------------------------
DELETE FROM tb_cpl_digital_evidence;
DELETE FROM tb_cpl_complaint;
DELETE FROM tb_cpl_complaint_protection;
DELETE FROM tb_cpl_reporter;
DELETE FROM tb_cpl_establishment;
DELETE FROM tb_cpl_modality;
COMMIT;


-- ---------------------------------------------------------------------
-- 1. CATALOGO DE MODALIDADES (valores del diccionario de datos)
-- ---------------------------------------------------------------------
INSERT INTO tb_cpl_modality VALUES (seq_cpl_modality.NEXTVAL, 'Cobro de cupo',        'CRITICAL');
INSERT INTO tb_cpl_modality VALUES (seq_cpl_modality.NEXTVAL, 'Extorsion telefonica', 'HIGH');
INSERT INTO tb_cpl_modality VALUES (seq_cpl_modality.NEXTVAL, 'Paradero',             'HIGH');
INSERT INTO tb_cpl_modality VALUES (seq_cpl_modality.NEXTVAL, 'Gota a gota',          'HIGH');
INSERT INTO tb_cpl_modality VALUES (seq_cpl_modality.NEXTVAL, 'Atentado',             'CRITICAL');
COMMIT;


-- ---------------------------------------------------------------------
-- 2. ESTABLECIMIENTOS, DENUNCIANTES, DENUNCIAS, PROTECCIONES, EVIDENCIAS
-- ---------------------------------------------------------------------
DECLARE
  TYPE t_vc  IS TABLE OF VARCHAR2(200);
  TYPE t_num IS TABLE OF NUMBER;

  -- Listas auxiliares para generar datos verosimiles
  v_fem    t_vc := t_vc('Rosa','Maria','Lucia','Carmen','Ana','Julia','Elena',
                        'Sofia','Patricia','Gloria');
  v_mas    t_vc := t_vc('Jose','Luis','Carlos','Juan','Pedro','Miguel','Jorge',
                        'Victor','Raul','Cesar');
  v_ape    t_vc := t_vc('Quispe','Huaman','Flores','Mamani','Rojas','Garcia',
                        'Torres','Vargas','Chavez','Ramos','Mendoza','Castillo');
  v_calle  t_vc := t_vc('Av. Canto Grande','Av. Proceres de la Independencia',
                        'Jr. Las Flores','Av. Wiesse','Jr. Los Amautas',
                        'Av. El Sol','Calle Los Jazmines','Av. Gran Chimu');
  v_alias  t_vc := t_vc('Los Malditos de Bayovar','Los Injertos del Cono',
                        'El Gringo','Los Pulpos','La Jauria',
                        'Los Terribles de Canto Rey');
  v_freq   t_vc := t_vc('DAILY','WEEKLY','MONTHLY','ONE_TIME');

  v_ev_type t_vc := t_vc('AUDIO_THREAT','CHAT_SCREENSHOT','SECURITY_VIDEO','PHOTO');
  v_ev_ext  t_vc := t_vc('.mp3','.png','.mp4','.jpg');
  v_ev_desc t_vc := t_vc('Audio de amenaza recibido por WhatsApp',
                         'Captura de chat con exigencia de pago',
                         'Video de camara de seguridad del local',
                         'Fotografia de mensaje intimidatorio');

  v_est_name t_vc := t_vc('Bodega Don Pepe','Paradero Linea 50',
                          'Taller Mecanico El Rapido','Ferreteria San Martin',
                          'Polleria El Buen Sabor','Paradero Linea 8',
                          'Minimarket La Economica','Taller de Motos Jhony',
                          'Restaurante El Norteno','Botica Santa Rosa',
                          'Paradero Empresa Santa Catalina','Vivienda Fam. Torres');
  v_est_type t_vc := t_vc('COMMERCE','TRANSPORT_STOP','WORKSHOP','COMMERCE',
                          'COMMERCE','TRANSPORT_STOP','COMMERCE','WORKSHOP',
                          'COMMERCE','COMMERCE','TRANSPORT_STOP','RESIDENCE');

  -- Datos existentes, cargados en memoria una sola vez
  v_sectors  t_num;
  v_officers t_vc;
  v_assocs   t_num;
  v_mods     t_num;
  v_reps     t_num;
  v_ests     t_num;

  -- Variables escalares: SQL solo recibe escalares (no BOOLEAN ni
  -- llamadas a subprogramas locales)
  v_sector   NUMBER;
  v_lat      NUMBER;
  v_lon      NUMBER;
  v_est      NUMBER;
  v_rep      NUMBER;
  v_prot     NUMBER;
  v_cur      NUMBER;
  v_amt      NUMBER;
  v_mod      NUMBER;
  v_assoc    NUMBER;
  v_anon     CHAR(1);
  v_gender   CHAR(1);
  v_inc      TIMESTAMP;
  v_reg      TIMESTAMP;
  v_cmp      NUMBER;
  v_ev       NUMBER;
  v_k        PLS_INTEGER;
  v_fname    VARCHAR2(50);
  v_lname    VARCHAR2(50);
  v_email    VARCHAR2(100);
  v_phone    VARCHAR2(15);
  v_addr     VARCHAR2(200);
  v_name     VARCHAR2(120);
  v_type     VARCHAR2(40);
  v_freq_v   VARCHAR2(30);
  v_alias_v  VARCHAR2(200);
  v_off      VARCHAR2(15);
  v_path     VARCHAR2(250);
  v_desc     VARCHAR2(200);
  v_n_anon   PLS_INTEGER := 0;
  v_n_ev     PLS_INTEGER := 0;

  -- Entero aleatorio entre 1 y p_n
  FUNCTION rnd(p_n NUMBER) RETURN PLS_INTEGER IS
  BEGIN
    RETURN TRUNC(DBMS_RANDOM.VALUE(1, p_n + 1));
  END;

  -- Punto aleatorio dentro del rectangulo de un sector
  PROCEDURE random_point(p_sector IN NUMBER, o_lat OUT NUMBER, o_lon OUT NUMBER) IS
    v_min_lat NUMBER; v_max_lat NUMBER; v_min_lon NUMBER; v_max_lon NUMBER;
  BEGIN
    SELECT min_lat, max_lat, min_lon, max_lon
      INTO v_min_lat, v_max_lat, v_min_lon, v_max_lon
      FROM tb_terr_sector
     WHERE sector_id = p_sector;
    o_lat := ROUND(v_min_lat + DBMS_RANDOM.VALUE * (v_max_lat - v_min_lat), 7);
    o_lon := ROUND(v_min_lon + DBMS_RANDOM.VALUE * (v_max_lon - v_min_lon), 7);
  END;

  -- Sector cuyo rectangulo contiene el punto (misma regla de asignacion por GPS)
  FUNCTION sector_of(p_lat NUMBER, p_lon NUMBER) RETURN NUMBER IS
    v_id NUMBER;
  BEGIN
    SELECT sector_id INTO v_id
      FROM tb_terr_sector
     WHERE p_lat BETWEEN min_lat AND max_lat
       AND p_lon BETWEEN min_lon AND max_lon
       AND ROWNUM = 1;
    RETURN v_id;
  END;

BEGIN
  DBMS_RANDOM.SEED(2026);

  SELECT sector_id   BULK COLLECT INTO v_sectors  FROM tb_terr_sector;
  SELECT officer_cip BULK COLLECT INTO v_officers FROM tb_staff_officer;
  SELECT assoc_id    BULK COLLECT INTO v_assocs   FROM tb_com_neighborhood_assoc;
  SELECT modality_id BULK COLLECT INTO v_mods     FROM tb_cpl_modality;

  IF v_sectors.COUNT = 0 OR v_officers.COUNT = 0 THEN
    RAISE_APPLICATION_ERROR(-20190,
      'Faltan sectores u oficiales: cargue primero los datos base.');
  END IF;

  -- 2.1 Establecimientos -------------------------------------------------
  FOR i IN 1 .. v_est_name.COUNT LOOP
    random_point(v_sectors(rnd(v_sectors.COUNT)), v_lat, v_lon);
    v_name := v_est_name(i);
    v_type := v_est_type(i);
    v_addr := v_calle(rnd(v_calle.COUNT)) || ' ' || rnd(2000);

    INSERT INTO tb_cpl_establishment
           (establishment_id, establishment_name, establishment_type,
            address, latitude, longitude)
    VALUES (seq_cpl_establishment.NEXTVAL, v_name, v_type,
            v_addr, v_lat, v_lon);
  END LOOP;

  -- 2.2 Denunciantes -----------------------------------------------------
  FOR i IN 1 .. 40 LOOP
    IF DBMS_RANDOM.VALUE < 0.5 THEN
      v_gender := 'H';
      v_fname  := v_mas(rnd(v_mas.COUNT));
    ELSE
      v_gender := 'M';
      v_fname  := v_fem(rnd(v_fem.COUNT));
    END IF;

    v_lname := v_ape(rnd(v_ape.COUNT));
    v_email := CASE WHEN MOD(i, 3) = 0 THEN NULL
                    ELSE LOWER(v_fname) || '.' || LOWER(v_lname) || i || '@correo.pe'
               END;
    v_lname := v_lname || ' ' || v_ape(rnd(v_ape.COUNT));
    v_phone := '9' || LPAD(TRUNC(DBMS_RANDOM.VALUE(0, 99999999)), 8, '0');
    v_addr  := v_calle(rnd(v_calle.COUNT)) || ' ' || rnd(2000) || ', SJL';

    INSERT INTO tb_cpl_reporter
           (id_reporter, personal_document_id, first_name, last_name,
            gender, address, phone_number, email)
    VALUES (seq_cpl_reporter.NEXTVAL, TO_CHAR(70000000 + i * 137), v_fname, v_lname,
            v_gender, v_addr, v_phone, v_email);
  END LOOP;

  SELECT id_reporter      BULK COLLECT INTO v_reps FROM tb_cpl_reporter;
  SELECT establishment_id BULK COLLECT INTO v_ests FROM tb_cpl_establishment;

  -- 2.3 Denuncias, protecciones y evidencias ----------------------------
  FOR i IN 1 .. 80 LOOP

    -- Ubicacion: 60% en un establecimiento afectado, 40% en via publica
    IF DBMS_RANDOM.VALUE < 0.6 THEN
      v_est := v_ests(rnd(v_ests.COUNT));
      SELECT latitude, longitude, address
        INTO v_lat, v_lon, v_addr
        FROM tb_cpl_establishment
       WHERE establishment_id = v_est;
      v_sector := sector_of(v_lat, v_lon);
    ELSE
      v_est    := NULL;
      v_sector := v_sectors(rnd(v_sectors.COUNT));
      random_point(v_sector, v_lat, v_lon);
      v_addr   := v_calle(rnd(v_calle.COUNT)) || ' cdra. ' || rnd(30);
    END IF;

    -- Moneda y monto: 60% PEN, 30% USD, 10% EUR (redondeado a decenas)
    v_amt := DBMS_RANDOM.VALUE;
    IF v_amt < 0.6 THEN
      v_cur := 1; v_amt := ROUND(DBMS_RANDOM.VALUE(50, 3000), -1);
    ELSIF v_amt < 0.9 THEN
      v_cur := 2; v_amt := ROUND(DBMS_RANDOM.VALUE(100, 2000), -1);
    ELSE
      v_cur := 3; v_amt := ROUND(DBMS_RANDOM.VALUE(100, 1500), -1);
    END IF;

    -- Fechas: suceso en los ultimos 12 meses; registro entre 1 y 48 h despues
    v_inc := LOCALTIMESTAMP - NUMTODSINTERVAL(DBMS_RANDOM.VALUE(1, 365), 'DAY');
    v_reg := LEAST(v_inc + NUMTODSINTERVAL(DBMS_RANDOM.VALUE(1, 48), 'HOUR'),
                   LOCALTIMESTAMP);

    -- Otros atributos
    v_mod     := v_mods(rnd(v_mods.COUNT));
    v_freq_v  := CASE WHEN DBMS_RANDOM.VALUE < 0.1 THEN NULL
                      ELSE v_freq(rnd(v_freq.COUNT)) END;
    v_alias_v := CASE WHEN DBMS_RANDOM.VALUE < 0.5 THEN NULL
                      ELSE v_alias(rnd(v_alias.COUNT)) END;
    v_assoc   := NULL;
    IF v_assocs.COUNT > 0 AND DBMS_RANDOM.VALUE < 0.15 THEN
      v_assoc := v_assocs(rnd(v_assocs.COUNT));
    END IF;

    -- Identidad: aprox. 30% anonimas con codigo protegido
    v_rep := v_reps(rnd(v_reps.COUNT));
    IF DBMS_RANDOM.VALUE < 0.3 THEN
      v_anon := 'Y';
      v_prot := seq_cpl_protection.NEXTVAL;
      v_off  := v_officers(rnd(v_officers.COUNT));

      INSERT INTO tb_cpl_complaint_protection
             (protected_code, id_reporter, date_approved, approved_by_officer)
      VALUES (v_prot, v_rep, v_reg, v_off);

      v_rep    := NULL;          -- la denuncia NO guarda la identidad
      v_n_anon := v_n_anon + 1;
    ELSE
      v_anon := 'N';
      v_prot := NULL;
    END IF;

    -- Denuncia (los triggers completan incident_location y amount_pen)
    v_cmp := seq_cpl_complaint.NEXTVAL;

    INSERT INTO tb_cpl_complaint
           (complaint_id, sector_id, modality_id, establishment_id, assoc_id,
            incident_date, registration_date, is_anonymous, currency_id,
            amount_original, payment_frequency, extortionist_alias,
            latitude, longitude, incident_address, id_reporter, protected_code)
    VALUES (v_cmp, v_sector, v_mod, v_est, v_assoc,
            v_inc, v_reg, v_anon, v_cur,
            v_amt, v_freq_v, v_alias_v,
            v_lat, v_lon, v_addr, v_rep, v_prot);

    -- Evidencias: entre 0 y 3 por denuncia
    FOR j IN 1 .. TRUNC(DBMS_RANDOM.VALUE(0, 4)) LOOP
      v_k    := rnd(v_ev_type.COUNT);
      v_ev   := seq_cpl_evidence.NEXTVAL;
      v_type := v_ev_type(v_k);
      v_path := '/evidencias/' || v_cmp || '_' || j || v_ev_ext(v_k);
      v_desc := v_ev_desc(v_k);
      v_off  := v_officers(rnd(v_officers.COUNT));

      INSERT INTO tb_cpl_digital_evidence
             (evidence_id, complaint_id, uploaded_by_cip, evidence_type,
              file_path, description, upload_date)
      VALUES (v_ev, v_cmp, v_off, v_type,
              v_path, v_desc,
              LEAST(v_reg + NUMTODSINTERVAL(j, 'HOUR'), LOCALTIMESTAMP));

      v_n_ev := v_n_ev + 1;
    END LOOP;
  END LOOP;

  COMMIT;

  DBMS_OUTPUT.PUT_LINE('Establecimientos : ' || v_est_name.COUNT);
  DBMS_OUTPUT.PUT_LINE('Denunciantes     : 40');
  DBMS_OUTPUT.PUT_LINE('Denuncias        : 80 (anonimas: ' || v_n_anon || ')');
  DBMS_OUTPUT.PUT_LINE('Evidencias       : ' || v_n_ev);
EXCEPTION
  WHEN OTHERS THEN
    ROLLBACK;
    DBMS_OUTPUT.PUT_LINE('Carga abortada: ' || SQLERRM);
    RAISE;
END;
/


-- ---------------------------------------------------------------------
-- 3. VERIFICACION DE LA CARGA
-- ---------------------------------------------------------------------

-- 3.1 Conteo por tabla
SELECT 'TB_CPL_MODALITY' AS tabla, COUNT(*) AS filas FROM tb_cpl_modality
UNION ALL SELECT 'TB_CPL_ESTABLISHMENT',        COUNT(*) FROM tb_cpl_establishment
UNION ALL SELECT 'TB_CPL_REPORTER',             COUNT(*) FROM tb_cpl_reporter
UNION ALL SELECT 'TB_CPL_COMPLAINT_PROTECTION', COUNT(*) FROM tb_cpl_complaint_protection
UNION ALL SELECT 'TB_CPL_COMPLAINT',            COUNT(*) FROM tb_cpl_complaint
UNION ALL SELECT 'TB_CPL_DIGITAL_EVIDENCE',     COUNT(*) FROM tb_cpl_digital_evidence;

-- 3.2 Variedad: anonimas vs. ordinarias y por moneda
SELECT c.is_anonymous, cu.currency_code, COUNT(*) AS denuncias,
       SUM(c.amount_original) AS total_original, SUM(c.amount_pen) AS total_soles
  FROM tb_cpl_complaint c
  JOIN tb_cfg_currency cu ON cu.currency_id = c.currency_id
 GROUP BY c.is_anonymous, cu.currency_code
 ORDER BY c.is_anonymous, cu.currency_code;

-- 3.3 Conversion a soles correcta (debe devolver 0 filas mientras no cambien las tasas)
SELECT c.complaint_id, c.amount_original, cu.exchange_rate_pen, c.amount_pen
  FROM tb_cpl_complaint c
  JOIN tb_cfg_currency cu ON cu.currency_id = c.currency_id
 WHERE c.amount_pen <> ROUND(c.amount_original * cu.exchange_rate_pen, 2);

-- 3.4 Cada denuncia cae dentro de su sector (debe devolver 0 filas)
SELECT c.complaint_id, c.sector_id, c.latitude, c.longitude
  FROM tb_cpl_complaint c
  JOIN tb_terr_sector s ON s.sector_id = c.sector_id
 WHERE c.latitude  NOT BETWEEN s.min_lat AND s.max_lat
    OR c.longitude NOT BETWEEN s.min_lon AND s.max_lon;

-- 3.5 Geometrias generadas por los triggers (ambos conteos deben ser 0)
SELECT (SELECT COUNT(*) FROM tb_cpl_complaint     WHERE incident_location IS NULL) AS cmp_sin_geom,
       (SELECT COUNT(*) FROM tb_cpl_establishment WHERE location_geom     IS NULL) AS est_sin_geom
  FROM dual;

-- 3.6 Distribucion mensual (insumo del futuro reporte por mes)
SELECT TO_CHAR(incident_date, 'YYYY-MM') AS mes, COUNT(*) AS denuncias
  FROM tb_cpl_complaint
 GROUP BY TO_CHAR(incident_date, 'YYYY-MM')
 ORDER BY mes;
