-- =============================================================================
-- 30_data.sql
-- System test data. Run as GEO_OWNER after creating the packages.
-- =============================================================================

-- =============================================================================
-- SECTION 1: Currencies, divisions, police stations, sectors, ranks and officers
-- Parent tables are loaded before child tables because of the foreign keys.
-- =============================================================================
SET DEFINE OFF

-- Currencies: id, code, name, soles per unit (the sol is the base).
INSERT INTO tb_cfg_currency VALUES (1, 'PEN', 'Peruvian Sol', 1.0000);
INSERT INTO tb_cfg_currency VALUES (2, 'USD', 'US Dollar',    3.7500);
INSERT INTO tb_cfg_currency VALUES (3, 'EUR', 'Euro',         4.1000);

-- Divisions: id, name, region.
INSERT INTO tb_org_division VALUES (1, 'DIVPOL LIMA ESTE 1 - SJL', 'REGION POLICIAL LIMA');
INSERT INTO tb_org_division VALUES (2, 'DIVPOL LIMA NORTE 1',      'REGION POLICIAL LIMA');

-- Police stations: id, division, name, address.
INSERT INTO tb_org_station VALUES (1, 1, 'COMISARIA CANTO REY',     'Av. Canto Rey 1200, San Juan de Lurigancho');
INSERT INTO tb_org_station VALUES (2, 1, 'COMISARIA SAN HILARION',  'Av. Los Jardines 850, San Juan de Lurigancho');
INSERT INTO tb_org_station VALUES (3, 2, 'COMISARIA LOS OLIVOS',    'Av. Carlos Izaguirre 600, Los Olivos');
INSERT INTO tb_org_station VALUES (4, 2, 'COMISARIA INDEPENDENCIA', 'Av. Tupac Amaru 2100, Independencia');

-- Sectors: contiguous 0.01-degree boxes that do not overlap. Sectors 1 and 3
-- share the border at latitude -11.97. The polygon is generated with an UPDATE
-- that uses pkg_org_mgmt.
INSERT INTO tb_terr_sector (sector_id, station_id, sector_name, min_lat, max_lat, min_lon, max_lon)
VALUES (1, 1, 'SECTOR 01 - CANTO REY COMERCIAL',     -11.9800, -11.9700, -77.0000, -76.9900);
INSERT INTO tb_terr_sector (sector_id, station_id, sector_name, min_lat, max_lat, min_lon, max_lon)
VALUES (2, 1, 'SECTOR 02 - CANTO REY RESIDENCIAL',   -11.9800, -11.9700, -76.9900, -76.9800);
INSERT INTO tb_terr_sector (sector_id, station_id, sector_name, min_lat, max_lat, min_lon, max_lon)
VALUES (3, 2, 'SECTOR 03 - SAN HILARION NORTE',      -11.9700, -11.9600, -77.0000, -76.9900);
INSERT INTO tb_terr_sector (sector_id, station_id, sector_name, min_lat, max_lat, min_lon, max_lon)
VALUES (4, 2, 'SECTOR 04 - SAN HILARION SUR',        -11.9700, -11.9600, -76.9900, -76.9800);
INSERT INTO tb_terr_sector (sector_id, station_id, sector_name, min_lat, max_lat, min_lon, max_lon)
VALUES (5, 3, 'SECTOR 05 - LOS OLIVOS PANAMERICANA', -11.9700, -11.9600, -77.0800, -77.0700);
INSERT INTO tb_terr_sector (sector_id, station_id, sector_name, min_lat, max_lat, min_lon, max_lon)
VALUES (6, 4, 'SECTOR 06 - INDEPENDENCIA TUPAC AMARU', -11.9900, -11.9800, -77.0600, -77.0500);

UPDATE tb_terr_sector
   SET polygon_area = pkg_org_mgmt.build_rect_polygon(min_lat, max_lat, min_lon, max_lon);

-- Ranks: id, name, command level (1 = highest).
INSERT INTO tb_staff_rank VALUES (1, 'Comandante', 1);
INSERT INTO tb_staff_rank VALUES (2, 'Mayor',      2);
INSERT INTO tb_staff_rank VALUES (3, 'Capitan',    3);
INSERT INTO tb_staff_rank VALUES (4, 'Teniente',   4);
INSERT INTO tb_staff_rank VALUES (5, 'Suboficial', 5);

-- Officers: CIP, first names, last names, rank, police station, supervisor CIP, specialty,
-- active cases. Supervisors are inserted first because the FK requires them to exist.
--   10000001 Comandante > 10000003 Mayor > 10000006 Capitan > 10000008 Teniente > 10000009 Suboficial
--   10000001 Comandante > 10000004 Mayor > 10000007 Capitan
--   10000002 Comandante > 10000005 Mayor > 10000010 Suboficial
INSERT INTO tb_staff_officer VALUES ('10000001', 'Ricardo', 'Salazar Pinto',  1, 1, NULL,       'INVESTIGADOR_CRIMINAL', 0);
INSERT INTO tb_staff_officer VALUES ('10000002', 'Maria',   'Quispe Huaman',  1, 3, NULL,       'INTELIGENCIA',           0);
INSERT INTO tb_staff_officer VALUES ('10000003', 'Jorge',   'Paredes Lozano', 2, 1, '10000001', 'INVESTIGADOR_CRIMINAL', 0);
INSERT INTO tb_staff_officer VALUES ('10000004', 'Ana',     'Rojas Cardenas', 2, 2, '10000001', 'ORDEN_PUBLICO',           0);
INSERT INTO tb_staff_officer VALUES ('10000005', 'Carmen',  'Flores Ortiz',   2, 3, '10000002', 'INVESTIGADOR_CRIMINAL', 0);
INSERT INTO tb_staff_officer VALUES ('10000006', 'Daniel',  'Vargas Soto',    3, 1, '10000003', 'INVESTIGADOR_CRIMINAL', 0);
INSERT INTO tb_staff_officer VALUES ('10000007', 'Rosa',    'Medina Chavez',  3, 2, '10000004', 'INTELIGENCIA',           0);
INSERT INTO tb_staff_officer VALUES ('10000008', 'Carlos',  'Huaman Diaz',    4, 1, '10000006', 'INVESTIGADOR_CRIMINAL', 0);
INSERT INTO tb_staff_officer VALUES ('10000009', 'Jose',    'Quiroz Tello',   5, 1, '10000008', 'INVESTIGADOR_CRIMINAL', 0);
INSERT INTO tb_staff_officer VALUES ('10000010', 'Rita',    'Gomez Salas',    5, 3, '10000005', 'ORDEN_PUBLICO',           0);

COMMIT;

-- =============================================================================
-- SECTION 2: Channels and neighborhood boards
-- =============================================================================
SET DEFINE OFF

INSERT INTO tb_com_channel VALUES (1, 'WhatsApp',                 '+51 987 000 111');
INSERT INTO tb_com_channel VALUES (2, 'Linea telefonica directa', '01-555-0100');
INSERT INTO tb_com_channel VALUES (3, 'Radio',                    'Frecuencia 98.5 FM');

-- id, sector, board name, coordinator, phone, authorized channel
INSERT INTO tb_com_neighborhood_assoc VALUES (1, 1, 'JUNTA VECINAL CANTO REY COMERCIAL',      'Mario Lopez Rivas', '987654001', 1);
INSERT INTO tb_com_neighborhood_assoc VALUES (2, 2, 'JUNTA VECINAL CANTO REY RESIDENCIAL',    'Elsa Campos Diaz',  '987654002', 2);
INSERT INTO tb_com_neighborhood_assoc VALUES (3, 3, 'JUNTA VECINAL SAN HILARION NORTE',       'Pablo Soto Vera',   '987654003', 1);
INSERT INTO tb_com_neighborhood_assoc VALUES (4, 5, 'JUNTA VECINAL LOS OLIVOS PANAMERICANA',  'Nelly Rios Mejia',  '987654004', 3);

COMMIT;

-- =============================================================================
-- SECTION 3: Modalities, establishments, reporters, complaints, protections and evidence
-- Loads 5 modalities, 12 establishments, 40 reporters and 80 complaints with their evidence.
-- Coordinates are generated inside the existing sectors with a fixed seed.
-- =============================================================================
SET SERVEROUTPUT ON



-- ---------------------------------------------------------------------
-- 1. MODALITY CATALOG (values from the data dictionary)
-- ---------------------------------------------------------------------
INSERT INTO tb_cpl_modality VALUES (seq_cpl_modality.NEXTVAL, 'Cobro de cupo',        'CRITICAL');
INSERT INTO tb_cpl_modality VALUES (seq_cpl_modality.NEXTVAL, 'Extorsion telefonica', 'HIGH');
INSERT INTO tb_cpl_modality VALUES (seq_cpl_modality.NEXTVAL, 'Paradero',             'HIGH');
INSERT INTO tb_cpl_modality VALUES (seq_cpl_modality.NEXTVAL, 'Gota a gota',          'HIGH');
INSERT INTO tb_cpl_modality VALUES (seq_cpl_modality.NEXTVAL, 'Atentado',             'CRITICAL');
COMMIT;


-- ---------------------------------------------------------------------
-- 2. ESTABLISHMENTS, REPORTERS, COMPLAINTS, PROTECTIONS, EVIDENCE
-- ---------------------------------------------------------------------
DECLARE
  TYPE t_vc  IS TABLE OF VARCHAR2(200);
  TYPE t_num IS TABLE OF NUMBER;

  -- Helper lists to generate plausible data
  v_female    t_vc := t_vc('Rosa','Maria','Lucia','Carmen','Ana','Julia','Elena',
                        'Sofia','Patricia','Gloria');
  v_male    t_vc := t_vc('Jose','Luis','Carlos','Juan','Pedro','Miguel','Jorge',
                        'Victor','Raul','Cesar');
  v_surnames    t_vc := t_vc('Quispe','Huaman','Flores','Mamani','Rojas','Garcia',
                        'Torres','Vargas','Chavez','Ramos','Mendoza','Castillo');
  v_streets  t_vc := t_vc('Av. Canto Grande','Av. Proceres de la Independencia',
                        'Jr. Las Flores','Av. Wiesse','Jr. Los Amautas',
                        'Av. El Sol','Calle Los Jazmines','Av. Gran Chimu');
  v_alias  t_vc := t_vc('Los Malditos de Bayovar','Los Injertos del Cono',
                        'El Gringo','Los Pulpos','La Jauria',
                        'Los Terribles de Canto Rey');
  v_freq   t_vc := t_vc('DIARIAMENTE','SEMANALMENTE','MENSUALMENTE','UNA VEZ');

  v_ev_type t_vc := t_vc('GRABACION DE AUDIO','SCREENSHOT','VIDEO DE SEGURIDAD','FOTO');
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

  -- Existing data, loaded into memory only once
  v_sectors  t_num;
  v_officers t_vc;
  v_assocs   t_num;
  v_mods     t_num;
  v_reps     t_num;
  v_ests     t_num;

  -- Scalar variables: SQL only receives scalars (not BOOLEAN or
  -- calls to local subprograms)
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

  -- Random integer between 1 and p_n
  FUNCTION rnd(p_n NUMBER) RETURN PLS_INTEGER IS
  BEGIN
    RETURN TRUNC(DBMS_RANDOM.VALUE(1, p_n + 1));
  END;

  -- Random point inside a sector's rectangle
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

  -- Sector whose rectangle contains the point (same GPS assignment rule)
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
      'Sectors or officers are missing: load the base data first.');
  END IF;

  -- 2.1 Establishments -------------------------------------------------
  FOR i IN 1 .. v_est_name.COUNT LOOP
    random_point(v_sectors(rnd(v_sectors.COUNT)), v_lat, v_lon);
    v_name := v_est_name(i);
    v_type := v_est_type(i);
    v_addr := v_streets(rnd(v_streets.COUNT)) || ' ' || rnd(2000);

    INSERT INTO tb_cpl_establishment
           (establishment_id, establishment_name, establishment_type,
            address, latitude, longitude)
    VALUES (seq_cpl_establishment.NEXTVAL, v_name, v_type,
            v_addr, v_lat, v_lon);
  END LOOP;

  -- 2.2 Reporters -----------------------------------------------------
  FOR i IN 1 .. 40 LOOP
    IF DBMS_RANDOM.VALUE < 0.5 THEN
      v_gender := 'H';
      v_fname  := v_male(rnd(v_male.COUNT));
    ELSE
      v_gender := 'M';
      v_fname  := v_female(rnd(v_female.COUNT));
    END IF;

    v_lname := v_surnames(rnd(v_surnames.COUNT));
    v_email := CASE WHEN MOD(i, 3) = 0 THEN NULL
                    ELSE LOWER(v_fname) || '.' || LOWER(v_lname) || i || '@correo.pe'
               END;
    v_lname := v_lname || ' ' || v_surnames(rnd(v_surnames.COUNT));
    v_phone := '9' || LPAD(TRUNC(DBMS_RANDOM.VALUE(0, 99999999)), 8, '0');
    v_addr  := v_streets(rnd(v_streets.COUNT)) || ' ' || rnd(2000) || ', SJL';

    INSERT INTO tb_cpl_reporter
           (id_reporter, personal_document_id, first_name, last_name,
            gender, address, phone_number, email)
    VALUES (seq_cpl_reporter.NEXTVAL, TO_CHAR(70000000 + i * 137), v_fname, v_lname,
            v_gender, v_addr, v_phone, v_email);
  END LOOP;

  SELECT id_reporter      BULK COLLECT INTO v_reps FROM tb_cpl_reporter;
  SELECT establishment_id BULK COLLECT INTO v_ests FROM tb_cpl_establishment;

  -- 2.3 Complaints, protections and evidence ----------------------------
  FOR i IN 1 .. 80 LOOP

    -- Location: 60% in an affected establishment, 40% on the public road
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
      v_addr   := v_streets(rnd(v_streets.COUNT)) || ' cdra. ' || rnd(30);
    END IF;

    -- Currency and amount: 60% PEN, 30% USD, 10% EUR (rounded to tens)
    v_amt := DBMS_RANDOM.VALUE;
    IF v_amt < 0.6 THEN
      v_cur := 1; v_amt := ROUND(DBMS_RANDOM.VALUE(50, 3000), -1);
    ELSIF v_amt < 0.9 THEN
      v_cur := 2; v_amt := ROUND(DBMS_RANDOM.VALUE(100, 2000), -1);
    ELSE
      v_cur := 3; v_amt := ROUND(DBMS_RANDOM.VALUE(100, 1500), -1);
    END IF;

    -- Dates: incident in the last 12 months; registration 1 to 48 h later
    v_inc := LOCALTIMESTAMP - NUMTODSINTERVAL(DBMS_RANDOM.VALUE(1, 365), 'DAY');
    v_reg := LEAST(v_inc + NUMTODSINTERVAL(DBMS_RANDOM.VALUE(1, 48), 'HOUR'),
                   LOCALTIMESTAMP);

    -- Other attributes
    v_mod     := v_mods(rnd(v_mods.COUNT));
    v_freq_v  := CASE WHEN DBMS_RANDOM.VALUE < 0.1 THEN NULL
                      ELSE v_freq(rnd(v_freq.COUNT)) END;
    v_alias_v := CASE WHEN DBMS_RANDOM.VALUE < 0.5 THEN NULL
                      ELSE v_alias(rnd(v_alias.COUNT)) END;
    v_assoc   := NULL;
    IF v_assocs.COUNT > 0 AND DBMS_RANDOM.VALUE < 0.15 THEN
      v_assoc := v_assocs(rnd(v_assocs.COUNT));
    END IF;

    -- Identity: approx. 30% anonymous with protected code
    v_rep := v_reps(rnd(v_reps.COUNT));
    IF DBMS_RANDOM.VALUE < 0.3 THEN
      v_anon := 'Y';
      v_prot := seq_cpl_protection.NEXTVAL;
      v_off  := v_officers(rnd(v_officers.COUNT));

      INSERT INTO tb_cpl_complaint_protection
             (protected_code, id_reporter, date_approved, approved_by_officer)
      VALUES (v_prot, v_rep, v_reg, v_off);

      v_rep    := NULL;          -- the complaint does NOT store the identity
      v_n_anon := v_n_anon + 1;
    ELSE
      v_anon := 'N';
      v_prot := NULL;
    END IF;

    -- Complaint (the triggers fill incident_location and amount_pen)
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

    -- Evidence: between 0 and 3 per complaint
    FOR j IN 1 .. TRUNC(DBMS_RANDOM.VALUE(0, 4)) LOOP
      v_k    := rnd(v_ev_type.COUNT);
      v_ev   := seq_cpl_evidence.NEXTVAL;
      v_type := v_ev_type(v_k);
      v_path := '/evidencias/' || v_cmp || '_' || j || v_ev_ext(v_k);
      v_desc := v_ev_desc(v_k);
      v_off  := v_officers(rnd(v_officers.COUNT));

      INSERT INTO tb_cpl_digital_evidence
             (evidence_id, complaint_id, uploaded_by_cip, evidence_type,
              file_path, description_ev, upload_date)
      VALUES (v_ev, v_cmp, v_off, v_type,
              v_path, v_desc,
              LEAST(v_reg + NUMTODSINTERVAL(j, 'HOUR'), LOCALTIMESTAMP));

      v_n_ev := v_n_ev + 1;
    END LOOP;
  END LOOP;

  COMMIT;

  DBMS_OUTPUT.PUT_LINE('Establishments   : ' || v_est_name.COUNT);
  DBMS_OUTPUT.PUT_LINE('Reporters        : 40');
  DBMS_OUTPUT.PUT_LINE('Complaints       : 80 (anonymous: ' || v_n_anon || ')');
  DBMS_OUTPUT.PUT_LINE('Evidence         : ' || v_n_ev);
EXCEPTION
  WHEN OTHERS THEN
    ROLLBACK;
    DBMS_OUTPUT.PUT_LINE('Load aborted: ' || SQLERRM);
    RAISE;
END;
/


-- ---------------------------------------------------------------------
-- 3. LOAD VERIFICATION
-- ---------------------------------------------------------------------

-- 3.1 Row count per table
SELECT 'TB_CPL_MODALITY' AS table_name, COUNT(*) AS row_count FROM tb_cpl_modality
UNION ALL SELECT 'TB_CPL_ESTABLISHMENT',        COUNT(*) FROM tb_cpl_establishment
UNION ALL SELECT 'TB_CPL_REPORTER',             COUNT(*) FROM tb_cpl_reporter
UNION ALL SELECT 'TB_CPL_COMPLAINT_PROTECTION', COUNT(*) FROM tb_cpl_complaint_protection
UNION ALL SELECT 'TB_CPL_COMPLAINT',            COUNT(*) FROM tb_cpl_complaint
UNION ALL SELECT 'TB_CPL_DIGITAL_EVIDENCE',     COUNT(*) FROM tb_cpl_digital_evidence;

-- 3.2 Variety: anonymous vs. ordinary and by currency
SELECT c.is_anonymous, cu.currency_code, COUNT(*) AS complaints,
       SUM(c.amount_original) AS total_original, SUM(c.amount_pen) AS total_pen
  FROM tb_cpl_complaint c
  JOIN tb_cfg_currency cu ON cu.currency_id = c.currency_id
 GROUP BY c.is_anonymous, cu.currency_code
 ORDER BY c.is_anonymous, cu.currency_code;

-- 3.3 Correct conversion to soles (must return 0 rows while the rates do not change)
SELECT c.complaint_id, c.amount_original, cu.exchange_rate_pen, c.amount_pen
  FROM tb_cpl_complaint c
  JOIN tb_cfg_currency cu ON cu.currency_id = c.currency_id
 WHERE c.amount_pen <> ROUND(c.amount_original * cu.exchange_rate_pen, 2);

-- 3.4 Every complaint falls inside its sector (must return 0 rows)
SELECT c.complaint_id, c.sector_id, c.latitude, c.longitude
  FROM tb_cpl_complaint c
  JOIN tb_terr_sector s ON s.sector_id = c.sector_id
 WHERE c.latitude  NOT BETWEEN s.min_lat AND s.max_lat
    OR c.longitude NOT BETWEEN s.min_lon AND s.max_lon;

-- 3.5 Geometries generated by the triggers (both counts must be 0)
SELECT (SELECT COUNT(*) FROM tb_cpl_complaint     WHERE incident_location IS NULL) AS complaints_without_geom,
       (SELECT COUNT(*) FROM tb_cpl_establishment WHERE location_geom     IS NULL) AS establishments_without_geom
  FROM dual;

-- 3.6 Monthly distribution (input for the future monthly report)
SELECT TO_CHAR(incident_date, 'YYYY-MM') AS report_month, COUNT(*) AS complaints
  FROM tb_cpl_complaint
 GROUP BY TO_CHAR(incident_date, 'YYYY-MM')
 ORDER BY report_month;

-- =============================================================================
-- SECTION 4: Investigation history, assignments and operation
-- Uses pkg_inv_mgmt on 9 REGISTRADO complaints:
--   #1-#2  stay in REGISTRADO
--   #3-#4  VALIDADO_COMISARIA
--   #5-#6  EN_INVESTIGACION with primary investigator
--   #7     INTERVENCION_PROGRAMADA with an operation
--   #8     DERIVADO_FISCALIA
--   #9     ARCHIVADO
-- =============================================================================
SET SERVEROUTPUT ON

DECLARE
  TYPE t_ids IS TABLE OF NUMBER;
  v_cpl    t_ids;
  v_dummy  NUMBER;
  v_sector NUMBER;
  c_chief  CONSTANT VARCHAR2(15) := '10000003';   -- signs assignments and status changes
  c_det1   CONSTANT VARCHAR2(15) := '10000006';
  c_det2   CONSTANT VARCHAR2(15) := '10000008';
BEGIN
  SELECT complaint_id BULK COLLECT INTO v_cpl
    FROM (SELECT complaint_id FROM tb_cpl_complaint
           WHERE current_status = 'REGISTRADO'
           ORDER BY complaint_id)
   WHERE ROWNUM <= 9;

  IF v_cpl.COUNT < 9 THEN
    RAISE_APPLICATION_ERROR(-20900, 'At least 9 REGISTRADO complaints are needed. Run the complaints section of 30_data.sql first.');
  END IF;

  -- Initial record of each complaint in the history.
  FOR i IN 1 .. v_cpl.COUNT LOOP
    pkg_inv_mgmt.log_initial_status(v_cpl(i), c_chief);
  END LOOP;

  -- #3 to #9: validation at the police station.
  FOR i IN 3 .. 9 LOOP
    pkg_inv_mgmt.change_status(v_cpl(i), 'VALIDADO_COMISARIA', c_chief, 'Validacion inicial por oficial de guardia');
  END LOOP;

  -- #5 to #9: assignment of the primary investigator (the complaint moves to EN_INVESTIGACION).
  v_dummy := pkg_inv_mgmt.assign_investigator(v_cpl(5), c_det1, c_chief);
  v_dummy := pkg_inv_mgmt.assign_investigator(v_cpl(6), c_det1, c_chief);
  v_dummy := pkg_inv_mgmt.assign_investigator(v_cpl(7), c_det2, c_chief);
  v_dummy := pkg_inv_mgmt.assign_investigator(v_cpl(8), c_det2, c_chief);
  v_dummy := pkg_inv_mgmt.assign_investigator(v_cpl(9), c_det2, c_chief);

  -- #7: scheduled intervention and operation in its sector.
  pkg_inv_mgmt.change_status(v_cpl(7), 'INTERVENCION_PROGRAMADA', c_det2, 'Se programa patrullaje focalizado en la zona');
  SELECT sector_id INTO v_sector FROM tb_cpl_complaint WHERE complaint_id = v_cpl(7);
  v_dummy := pkg_inv_mgmt.register_operation(v_sector, c_det2, 'PATRULLAJE FOCALIZADO', SYSTIMESTAMP + INTERVAL '1' DAY,
                                             pkg_inv_mgmt.t_id_list(v_cpl(7)));

  -- #8: referral to the prosecutor's office.
  pkg_inv_mgmt.change_status(v_cpl(8), 'DERIVADO_FISCALIA', c_det2, 'Se deriva el caso al Ministerio Publico');

  -- #9: case archived (releases the investigator's slot).
  pkg_inv_mgmt.change_status(v_cpl(9), 'ARCHIVADO', c_det2, 'Archivo por falta de elementos probatorios');

  COMMIT;
  DBMS_OUTPUT.PUT_LINE('Investigation load completed on 9 complaints.');
EXCEPTION
  WHEN OTHERS THEN
    ROLLBACK;
    DBMS_OUTPUT.PUT_LINE('Load aborted: ' || SQLERRM);
    RAISE;
END;
/

