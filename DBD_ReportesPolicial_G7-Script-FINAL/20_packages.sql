-- =============================================================================
-- 20_packages.sql
-- Packages pkg_org_mgmt, pkg_cpl_mgmt and pkg_inv_mgmt. Run as GEO_OWNER.
-- =============================================================================

-- =============================================================================
-- SECTION 1: pkg_org_mgmt
-- Currency, division, station, sector, rank and officer.
-- =============================================================================

CREATE OR REPLACE PACKAGE pkg_org_mgmt AS

  -- Currency.
  PROCEDURE insert_currency (p_code IN VARCHAR2, p_name IN VARCHAR2, p_rate IN NUMBER, p_id OUT NUMBER);
  PROCEDURE update_currency (p_id IN NUMBER, p_name IN VARCHAR2, p_rate IN NUMBER);
  PROCEDURE delete_currency (p_id IN NUMBER);
  -- Converts an amount to soles using the currency rate (2 decimals).
  FUNCTION  convert_to_pen  (p_amount IN NUMBER, p_currency_id IN NUMBER) RETURN NUMBER;

  -- Division and station.
  PROCEDURE insert_division (p_name IN VARCHAR2, p_region IN VARCHAR2, p_id OUT NUMBER);
  PROCEDURE update_division (p_id IN NUMBER, p_name IN VARCHAR2, p_region IN VARCHAR2);
  PROCEDURE delete_division (p_id IN NUMBER);
  PROCEDURE insert_station  (p_division_id IN NUMBER, p_name IN VARCHAR2, p_address IN VARCHAR2, p_id OUT NUMBER);
  PROCEDURE update_station  (p_id IN NUMBER, p_division_id IN NUMBER, p_name IN VARCHAR2, p_address IN VARCHAR2);
  PROCEDURE delete_station  (p_id IN NUMBER);

  -- Sector: takes the box; the polygon is built automatically.
  PROCEDURE insert_sector (p_station_id IN NUMBER, p_name IN VARCHAR2,
                           p_min_lat IN NUMBER, p_max_lat IN NUMBER,
                           p_min_lon IN NUMBER, p_max_lon IN NUMBER, p_id OUT NUMBER);
  PROCEDURE update_sector (p_id IN NUMBER, p_station_id IN NUMBER, p_name IN VARCHAR2,
                           p_min_lat IN NUMBER, p_max_lat IN NUMBER,
                           p_min_lon IN NUMBER, p_max_lon IN NUMBER);
  PROCEDURE delete_sector (p_id IN NUMBER);

  -- Returns the sector containing the GPS point, or NULL.
  FUNCTION  find_sector_by_location (p_latitude IN NUMBER, p_longitude IN NUMBER) RETURN NUMBER;
  -- Builds a sector's rectangular polygon from its box (SRID 4326).
  FUNCTION  build_rect_polygon (p_min_lat IN NUMBER, p_max_lat IN NUMBER,
                                p_min_lon IN NUMBER, p_max_lon IN NUMBER) RETURN SDO_GEOMETRY;

  -- Rank.
  PROCEDURE insert_rank (p_name IN VARCHAR2, p_level IN NUMBER, p_id OUT NUMBER);
  PROCEDURE update_rank (p_id IN NUMBER, p_name IN VARCHAR2, p_level IN NUMBER);
  PROCEDURE delete_rank (p_id IN NUMBER);

  -- Officer: the supervisor must have a higher rank.
  PROCEDURE insert_officer (p_cip IN VARCHAR2, p_first_name IN VARCHAR2, p_last_name IN VARCHAR2,
                            p_rank_id IN NUMBER, p_station_id IN NUMBER,
                            p_supervisor_cip IN VARCHAR2, p_specialty IN VARCHAR2);
  PROCEDURE update_officer (p_cip IN VARCHAR2, p_first_name IN VARCHAR2, p_last_name IN VARCHAR2,
                            p_rank_id IN NUMBER, p_station_id IN NUMBER,
                            p_supervisor_cip IN VARCHAR2, p_specialty IN VARCHAR2);
  PROCEDURE delete_officer (p_cip IN VARCHAR2);

END pkg_org_mgmt;
/

CREATE OR REPLACE PACKAGE BODY pkg_org_mgmt AS

  -- ===================================================================
  -- PRIVATE SUBPROGRAMS
  -- ===================================================================

  -- Raises -20001 if the previous UPDATE/DELETE affected no rows.
  PROCEDURE check_updated (p_entity IN VARCHAR2, p_key IN VARCHAR2) IS
  BEGIN
    IF SQL%ROWCOUNT = 0 THEN
      RAISE_APPLICATION_ERROR(-20001, p_entity || ' no encontrado: ' || p_key);
    END IF;
  END check_updated;

  -- Checks the supervisor has a lower hierarchy_level (higher rank).
  PROCEDURE check_supervisor (p_rank_id IN NUMBER, p_supervisor_cip IN VARCHAR2) IS
    v_super_level NUMBER;
    v_level       NUMBER;
  BEGIN
    IF p_supervisor_cip IS NULL THEN
      RETURN;
    END IF;
    SELECT r.hierarchy_level INTO v_super_level
      FROM tb_staff_officer o JOIN tb_staff_rank r ON r.rank_id = o.rank_id
     WHERE o.officer_cip = p_supervisor_cip;
    SELECT hierarchy_level INTO v_level FROM tb_staff_rank WHERE rank_id = p_rank_id;
    IF v_super_level >= v_level THEN
      RAISE_APPLICATION_ERROR(-20002, 'El supervisor ' || p_supervisor_cip || ' debe tener un rango mas alto');
    END IF;
  EXCEPTION
    WHEN NO_DATA_FOUND THEN
      RAISE_APPLICATION_ERROR(-20001, 'Supervisor o rank no encontrado');
  END check_supervisor;

  -- ---------------- Currency ----------------
  PROCEDURE insert_currency (p_code IN VARCHAR2, p_name IN VARCHAR2, p_rate IN NUMBER, p_id OUT NUMBER) IS
  BEGIN
    p_id := seq_cfg_currency.NEXTVAL;
    INSERT INTO tb_cfg_currency VALUES (p_id, UPPER(p_code), p_name, p_rate);
  END insert_currency;

  PROCEDURE update_currency (p_id IN NUMBER, p_name IN VARCHAR2, p_rate IN NUMBER) IS
  BEGIN
    IF p_id = 1 AND p_rate <> 1 THEN
      RAISE_APPLICATION_ERROR(-20002, 'PEN es la moneda base: su tasa debe ser 1');
    END IF;
    UPDATE tb_cfg_currency SET currency_name = p_name, exchange_rate_pen = p_rate WHERE currency_id = p_id;
    check_updated('Currency', p_id);
  END update_currency;

  PROCEDURE delete_currency (p_id IN NUMBER) IS
  BEGIN
    DELETE FROM tb_cfg_currency WHERE currency_id = p_id;
    check_updated('Currency', p_id);
  END delete_currency;

  -- Amount in soles = amount x currency rate.
  FUNCTION convert_to_pen (p_amount IN NUMBER, p_currency_id IN NUMBER) RETURN NUMBER IS
    v_rate tb_cfg_currency.exchange_rate_pen%TYPE;
  BEGIN
    SELECT exchange_rate_pen INTO v_rate FROM tb_cfg_currency WHERE currency_id = p_currency_id;
    RETURN ROUND(p_amount * v_rate, 2);
  EXCEPTION
    WHEN NO_DATA_FOUND THEN
      RAISE_APPLICATION_ERROR(-20001, 'Moneda no encontrada: ' || p_currency_id);
  END convert_to_pen;

  -- Division and station.
  PROCEDURE insert_division (p_name IN VARCHAR2, p_region IN VARCHAR2, p_id OUT NUMBER) IS
  BEGIN
    p_id := seq_org_division.NEXTVAL;
    INSERT INTO tb_org_division VALUES (p_id, p_name, p_region);
  END insert_division;

  PROCEDURE update_division (p_id IN NUMBER, p_name IN VARCHAR2, p_region IN VARCHAR2) IS
  BEGIN
    UPDATE tb_org_division SET division_name = p_name, region_name = p_region WHERE division_id = p_id;
    check_updated('Division', p_id);
  END update_division;

  PROCEDURE delete_division (p_id IN NUMBER) IS
  BEGIN
    DELETE FROM tb_org_division WHERE division_id = p_id;
    check_updated('Division', p_id);
  END delete_division;

  PROCEDURE insert_station (p_division_id IN NUMBER, p_name IN VARCHAR2, p_address IN VARCHAR2, p_id OUT NUMBER) IS
  BEGIN
    p_id := seq_org_station.NEXTVAL;
    INSERT INTO tb_org_station VALUES (p_id, p_division_id, p_name, p_address);
  END insert_station;

  PROCEDURE update_station (p_id IN NUMBER, p_division_id IN NUMBER, p_name IN VARCHAR2, p_address IN VARCHAR2) IS
  BEGIN
    UPDATE tb_org_station SET division_id = p_division_id, station_name = p_name, address = p_address
     WHERE station_id = p_id;
    check_updated('Station', p_id);
  END update_station;

  PROCEDURE delete_station (p_id IN NUMBER) IS
  BEGIN
    DELETE FROM tb_org_station WHERE station_id = p_id;
    check_updated('Station', p_id);
  END delete_station;

  -- Sector.
  PROCEDURE insert_sector (p_station_id IN NUMBER, p_name IN VARCHAR2,
                           p_min_lat IN NUMBER, p_max_lat IN NUMBER,
                           p_min_lon IN NUMBER, p_max_lon IN NUMBER, p_id OUT NUMBER) IS
  BEGIN
    p_id := seq_terr_sector.NEXTVAL;
    INSERT INTO tb_terr_sector
    VALUES (p_id, p_station_id, p_name, p_min_lat, p_max_lat, p_min_lon, p_max_lon,
            build_rect_polygon(p_min_lat, p_max_lat, p_min_lon, p_max_lon));
  END insert_sector;

  -- Changing the box regenerates the polygon.
  PROCEDURE update_sector (p_id IN NUMBER, p_station_id IN NUMBER, p_name IN VARCHAR2,
                           p_min_lat IN NUMBER, p_max_lat IN NUMBER,
                           p_min_lon IN NUMBER, p_max_lon IN NUMBER) IS
  BEGIN
    UPDATE tb_terr_sector
       SET station_id = p_station_id, sector_name = p_name,
           min_lat = p_min_lat, max_lat = p_max_lat, min_lon = p_min_lon, max_lon = p_max_lon,
           polygon_area = build_rect_polygon(p_min_lat, p_max_lat, p_min_lon, p_max_lon)
     WHERE sector_id = p_id;
    check_updated('Sector', p_id);
  END update_sector;

  PROCEDURE delete_sector (p_id IN NUMBER) IS
  BEGIN
    DELETE FROM tb_terr_sector WHERE sector_id = p_id;
    check_updated('Sector', p_id);
  END delete_sector;

  -- Rectangle polygon: x = longitude, y = latitude, closed with the first point.
  FUNCTION build_rect_polygon (p_min_lat IN NUMBER, p_max_lat IN NUMBER,
                               p_min_lon IN NUMBER, p_max_lon IN NUMBER) RETURN SDO_GEOMETRY IS
  BEGIN
    RETURN SDO_GEOMETRY(2003, 4326, NULL, SDO_ELEM_INFO_ARRAY(1, 1003, 1),
             SDO_ORDINATE_ARRAY(p_min_lon, p_min_lat, p_max_lon, p_min_lat,
                                p_max_lon, p_max_lat, p_min_lon, p_max_lat,
                                p_min_lon, p_min_lat));
  END build_rect_polygon;

  -- Finds the sector by box ([min, max) interval) and confirms with the polygon (SDO_ANYINTERACT).
  FUNCTION find_sector_by_location (p_latitude IN NUMBER, p_longitude IN NUMBER) RETURN NUMBER IS
    v_point     SDO_GEOMETRY;
    v_sector_id NUMBER;
  BEGIN
    IF p_latitude NOT BETWEEN -90 AND 90 OR p_longitude NOT BETWEEN -180 AND 180 THEN
      RAISE_APPLICATION_ERROR(-20002, 'Coordenadas invalidas');
    END IF;
    v_point := SDO_GEOMETRY(2001, 4326, SDO_POINT_TYPE(p_longitude, p_latitude, NULL), NULL, NULL);

    SELECT sector_id
      INTO v_sector_id
      FROM tb_terr_sector
     WHERE p_latitude  >= min_lat AND p_latitude  < max_lat
       AND p_longitude >= min_lon AND p_longitude < max_lon
       AND SDO_ANYINTERACT(polygon_area, v_point) = 'TRUE';
    RETURN v_sector_id;
  EXCEPTION
    WHEN NO_DATA_FOUND THEN
      RETURN NULL;
  END find_sector_by_location;

  -- ---------------- Rank ----------------
  PROCEDURE insert_rank (p_name IN VARCHAR2, p_level IN NUMBER, p_id OUT NUMBER) IS
  BEGIN
    p_id := seq_staff_rank.NEXTVAL;
    INSERT INTO tb_staff_rank VALUES (p_id, p_name, p_level);
  END insert_rank;

  PROCEDURE update_rank (p_id IN NUMBER, p_name IN VARCHAR2, p_level IN NUMBER) IS
  BEGIN
    UPDATE tb_staff_rank SET rank_name = p_name, hierarchy_level = p_level WHERE rank_id = p_id;
    check_updated('Rank', p_id);
  END update_rank;

  PROCEDURE delete_rank (p_id IN NUMBER) IS
  BEGIN
    DELETE FROM tb_staff_rank WHERE rank_id = p_id;
    check_updated('Rank', p_id);
  END delete_rank;

  -- ---------------- Officer ----------------
  -- Inserts the officer with active_case_count = 0.
  PROCEDURE insert_officer (p_cip IN VARCHAR2, p_first_name IN VARCHAR2, p_last_name IN VARCHAR2,
                            p_rank_id IN NUMBER, p_station_id IN NUMBER,
                            p_supervisor_cip IN VARCHAR2, p_specialty IN VARCHAR2) IS
  BEGIN
    check_supervisor(p_rank_id, p_supervisor_cip);
    INSERT INTO tb_staff_officer
    VALUES (p_cip, p_first_name, p_last_name, p_rank_id, p_station_id, p_supervisor_cip, p_specialty, 0);
  END insert_officer;

  -- Updates officer data, including station, rank and supervisor.
  PROCEDURE update_officer (p_cip IN VARCHAR2, p_first_name IN VARCHAR2, p_last_name IN VARCHAR2,
                            p_rank_id IN NUMBER, p_station_id IN NUMBER,
                            p_supervisor_cip IN VARCHAR2, p_specialty IN VARCHAR2) IS
  BEGIN
    check_supervisor(p_rank_id, p_supervisor_cip);
    UPDATE tb_staff_officer
       SET first_name = p_first_name, last_name = p_last_name, rank_id = p_rank_id,
           station_id = p_station_id, supervisor_cip = p_supervisor_cip, specialty = p_specialty
     WHERE officer_cip = p_cip;
    check_updated('Officer', p_cip);
  END update_officer;

  PROCEDURE delete_officer (p_cip IN VARCHAR2) IS
  BEGIN
    DELETE FROM tb_staff_officer WHERE officer_cip = p_cip;
    check_updated('Officer', p_cip);
  END delete_officer;

END pkg_org_mgmt;
/
SHOW ERRORS PACKAGE pkg_org_mgmt
SHOW ERRORS PACKAGE BODY pkg_org_mgmt


-- =============================================================================
-- SECTION 2: pkg_cpl_mgmt
-- Modalities, establishments, reporters, protections, complaints, evidence and reports in soles.
-- =============================================================================

CREATE OR REPLACE PACKAGE pkg_cpl_mgmt AS

  -- Complaint error codes:
  --   -20101  unknown currency (trigger trg_cpl_complaint_pen)
  --   -20110  record not found
  --   -20111  record has dependents: cannot delete
  --   -20112  reference to a missing parent record (FK)
  --   -20113  no sector contains the GPS point
  --   -20114  anonymous complaint without an approving officer
  --   -20115  duplicate value (PK/UK)
  --   -20116  invalid data (CHECK or NOT NULL)
  --   -20117  invalid parameter
  --   -20118  complaint not editable in its current status
  --   -20119  access denied to a protected reporter's identity
  --   -20199  unexpected error

  -- ---------------- MODALITIES ----------------
  FUNCTION  ins_modality (p_name     tb_cpl_modality.modality_name%TYPE,
                          p_severity tb_cpl_modality.severity_level%TYPE)
            RETURN tb_cpl_modality.modality_id%TYPE;
  PROCEDURE upd_modality (p_modality_id tb_cpl_modality.modality_id%TYPE,
                          p_name        tb_cpl_modality.modality_name%TYPE,
                          p_severity    tb_cpl_modality.severity_level%TYPE);
  PROCEDURE del_modality (p_modality_id tb_cpl_modality.modality_id%TYPE);
  FUNCTION  get_modality (p_modality_id tb_cpl_modality.modality_id%TYPE)
            RETURN tb_cpl_modality%ROWTYPE;

  -- ---------------- ESTABLISHMENTS ----------------
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

  -- ---------------- REPORTERS ----------------
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

  -- ---------------- PROTECTIONS (protected code) ----------------
  FUNCTION  ins_protection (p_id_reporter tb_cpl_complaint_protection.id_reporter%TYPE,
                            p_officer_cip tb_cpl_complaint_protection.approved_by_officer%TYPE)
            RETURN tb_cpl_complaint_protection.protected_code%TYPE;
  PROCEDURE upd_protection (p_protected_code tb_cpl_complaint_protection.protected_code%TYPE,
                            p_officer_cip    tb_cpl_complaint_protection.approved_by_officer%TYPE);
  PROCEDURE del_protection (p_protected_code tb_cpl_complaint_protection.protected_code%TYPE);
  FUNCTION  get_protection (p_protected_code tb_cpl_complaint_protection.protected_code%TYPE)
            RETURN tb_cpl_complaint_protection%ROWTYPE;

  -- ---------------- COMPLAINTS ----------------
  -- Returns the sector whose box (min/max lat/lon) contains the GPS point.
  FUNCTION  find_sector (p_latitude  tb_cpl_complaint.latitude%TYPE,
                         p_longitude tb_cpl_complaint.longitude%TYPE)
            RETURN tb_cpl_complaint.sector_id%TYPE;

  -- Registers a complaint. If p_is_anonymous = 'Y', the identity is stored only in
  -- TB_CPL_COMPLAINT_PROTECTION and the complaint gets the protected code.
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

  -- Edits the incident data (REGISTRADO status only).
  PROCEDURE upd_complaint (
              p_complaint_id       tb_cpl_complaint.complaint_id%TYPE,
              p_modality_id        tb_cpl_complaint.modality_id%TYPE,
              p_currency_id        tb_cpl_complaint.currency_id%TYPE,
              p_amount_original    tb_cpl_complaint.amount_original%TYPE,
              p_payment_frequency  tb_cpl_complaint.payment_frequency%TYPE,
              p_extortionist_alias tb_cpl_complaint.extortionist_alias%TYPE,
              p_establishment_id   tb_cpl_complaint.establishment_id%TYPE,
              p_assoc_id           tb_cpl_complaint.assoc_id%TYPE);

  -- Changes the location and recalculates the sector (REGISTRADO only).
  PROCEDURE upd_complaint_location (
              p_complaint_id     tb_cpl_complaint.complaint_id%TYPE,
              p_latitude         tb_cpl_complaint.latitude%TYPE,
              p_longitude        tb_cpl_complaint.longitude%TYPE,
              p_incident_address tb_cpl_complaint.incident_address%TYPE);

  -- Deletes the complaint with its evidence and protection (REGISTRADO only).
  PROCEDURE del_complaint (p_complaint_id tb_cpl_complaint.complaint_id%TYPE);

  FUNCTION  get_complaint (p_complaint_id tb_cpl_complaint.complaint_id%TYPE)
            RETURN tb_cpl_complaint%ROWTYPE;

  -- Returns the reporter's name, masked if the complaint is anonymous.
  FUNCTION  reporter_display (p_complaint_id tb_cpl_complaint.complaint_id%TYPE)
            RETURN VARCHAR2;

  -- Lists complaints with the identity masked on anonymous ones.
  FUNCTION  list_complaints (p_sector_id tb_cpl_complaint.sector_id%TYPE DEFAULT NULL)
            RETURN SYS_REFCURSOR;

  -- ---------------- EVIDENCE ----------------
  FUNCTION  ins_evidence (p_complaint_id tb_cpl_digital_evidence.complaint_id%TYPE,
                          p_uploaded_by  tb_cpl_digital_evidence.uploaded_by_cip%TYPE,
                          p_type         tb_cpl_digital_evidence.evidence_type%TYPE,
                          p_file_path    tb_cpl_digital_evidence.file_path%TYPE,
                          p_description  tb_cpl_digital_evidence.description_ev%TYPE)
            RETURN tb_cpl_digital_evidence.evidence_id%TYPE;
  PROCEDURE upd_evidence (p_evidence_id  tb_cpl_digital_evidence.evidence_id%TYPE,
                          p_type         tb_cpl_digital_evidence.evidence_type%TYPE,
                          p_file_path    tb_cpl_digital_evidence.file_path%TYPE,
                          p_description  tb_cpl_digital_evidence.description_ev%TYPE);
  PROCEDURE del_evidence (p_evidence_id  tb_cpl_digital_evidence.evidence_id%TYPE);
  FUNCTION  get_evidence (p_evidence_id  tb_cpl_digital_evidence.evidence_id%TYPE)
            RETURN tb_cpl_digital_evidence%ROWTYPE;

  -- ---------------- REPORTS (amounts in soles) ----------------
  PROCEDURE rpt_by_sector   (p_date_from DATE DEFAULT NULL, p_date_to DATE DEFAULT NULL);
  PROCEDURE rpt_by_modality (p_date_from DATE DEFAULT NULL, p_date_to DATE DEFAULT NULL);
  PROCEDURE rpt_by_month    (p_year NUMBER DEFAULT NULL);

END pkg_cpl_mgmt;
/

CREATE OR REPLACE PACKAGE BODY pkg_cpl_mgmt AS

  -- Report cursors. The date filter is in the LEFT JOIN's ON clause so
  -- sectors/modalities without complaints still appear.
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
  -- PRIVATE SUBPROGRAMS
  -- ===================================================================

  -- Maps Oracle errors to the complaint error codes.
  PROCEDURE raise_dml_error (p_context VARCHAR2, p_code NUMBER, p_msg VARCHAR2) IS
  BEGIN
    IF p_code BETWEEN -20999 AND -20000 THEN
      -- Own error (package or trigger): re-raised with its code.
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

  -- Raises -20110 if an UPDATE/DELETE affected no rows.
  PROCEDURE check_found (p_rows NUMBER, p_entity VARCHAR2, p_id VARCHAR2) IS
  BEGIN
    IF p_rows = 0 THEN
      RAISE_APPLICATION_ERROR(-20110, p_entity || ' ' || p_id || ' no existe.');
    END IF;
  END check_found;

  -- Formats an amount as soles.
  FUNCTION fmt_pen (p_amount NUMBER) RETURN VARCHAR2 IS
  BEGIN
    RETURN 'S/ ' || TO_CHAR(NVL(p_amount, 0), 'FM9,999,999,990.00');
  END fmt_pen;

  -- Checks the complaint exists and is REGISTRADO, and locks its row.
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
  -- MODALITIES
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
  -- ESTABLISHMENTS
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
  -- REPORTERS
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
    v_row  tb_cpl_reporter%ROWTYPE;
    v_prot PLS_INTEGER;
  BEGIN
    -- A protected reporter's identity is visible only to the schema owner or the chief.
    -- (The package runs with owner rights, so the connected user is checked.)
    SELECT COUNT(*) INTO v_prot FROM tb_cpl_complaint_protection WHERE id_reporter = p_id_reporter;
    IF v_prot > 0 AND SYS_CONTEXT('USERENV', 'SESSION_USER') NOT IN ('GEO_OWNER', 'GEO_CHIEF') THEN
      RAISE_APPLICATION_ERROR(-20119, 'Sin permiso para ver la identidad de un denunciante protegido.');
    END IF;
    SELECT * INTO v_row FROM tb_cpl_reporter WHERE id_reporter = p_id_reporter;
    RETURN v_row;
  EXCEPTION
    WHEN NO_DATA_FOUND THEN
      RAISE_APPLICATION_ERROR(-20110, 'Denunciante ' || p_id_reporter || ' no existe.');
  END get_reporter;


  -- ===================================================================
  -- PROTECTIONS
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
    -- Links the protected code to the real reporter: restricted access.
    IF SYS_CONTEXT('USERENV', 'SESSION_USER') NOT IN ('GEO_OWNER', 'GEO_CHIEF') THEN
      RAISE_APPLICATION_ERROR(-20119, 'Sin permiso para ver datos de proteccion.');
    END IF;
    SELECT * INTO v_row FROM tb_cpl_complaint_protection
     WHERE protected_code = p_protected_code;
    RETURN v_row;
  EXCEPTION
    WHEN NO_DATA_FOUND THEN
      RAISE_APPLICATION_ERROR(-20110, 'Proteccion ' || p_protected_code || ' no existe.');
  END get_protection;


  -- ===================================================================
  -- COMPLAINTS
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
    -- On failure, this registration's steps are rolled back without affecting the rest of the transaction.
    SAVEPOINT sp_register;

    -- Validations.
    IF p_is_anonymous IS NULL OR p_is_anonymous NOT IN ('Y', 'N') THEN
      RAISE_APPLICATION_ERROR(-20117, 'p_is_anonymous debe ser Y o N.');
    END IF;

    IF p_is_anonymous = 'Y' AND p_officer_cip IS NULL THEN
      RAISE_APPLICATION_ERROR(-20114, 'Una denuncia anonima requiere el CIP del ' ||
        'oficial que aprueba la reserva de identidad.');
    END IF;

    -- Assign the sector by GPS.
    v_sector := find_sector(p_latitude, p_longitude);

    -- Reporter: reused if the document is already registered.
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

    -- For anonymous complaints the identity stays only in the protection; the complaint stores the code.
    IF p_is_anonymous = 'Y' THEN
      v_prot := ins_protection(v_rep, p_officer_cip);
      v_rep  := NULL;
    ELSE
      v_prot := NULL;
    END IF;

    -- Complaint (triggers fill incident_location and amount_pen).
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

    -- Delete child records first.
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
  -- EVIDENCE
  -- ===================================================================
  FUNCTION ins_evidence (p_complaint_id tb_cpl_digital_evidence.complaint_id%TYPE,
                         p_uploaded_by  tb_cpl_digital_evidence.uploaded_by_cip%TYPE,
                         p_type         tb_cpl_digital_evidence.evidence_type%TYPE,
                         p_file_path    tb_cpl_digital_evidence.file_path%TYPE,
                         p_description  tb_cpl_digital_evidence.description_ev%TYPE)
    RETURN tb_cpl_digital_evidence.evidence_id%TYPE IS
    v_id tb_cpl_digital_evidence.evidence_id%TYPE;
  BEGIN
    INSERT INTO tb_cpl_digital_evidence
           (evidence_id, complaint_id, uploaded_by_cip, evidence_type,
            file_path, description_ev)
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
                          p_description  tb_cpl_digital_evidence.description_ev%TYPE) IS
    v_rows PLS_INTEGER;
  BEGIN
    BEGIN
      UPDATE tb_cpl_digital_evidence
         SET evidence_type = p_type,
             file_path     = p_file_path,
             description_ev = p_description
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
  -- REPORTS
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
    v_rows := c_rpt_sector%ROWCOUNT;
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
    -- Grand total, to compute each modality's share.
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
SHOW ERRORS PACKAGE pkg_cpl_mgmt
SHOW ERRORS PACKAGE BODY pkg_cpl_mgmt


-- =============================================================================
-- SECTION 3: pkg_inv_mgmt
-- Investigation statuses, investigator assignment and operations.
-- =============================================================================

CREATE OR REPLACE PACKAGE pkg_inv_mgmt AS

  -- ---------------- Investigation types and constants ----------------
  TYPE t_id_list IS TABLE OF NUMBER;

  -- Complaint statuses.
  c_registrado        CONSTANT VARCHAR2(30) := 'REGISTRADO';
  c_validado          CONSTANT VARCHAR2(30) := 'VALIDADO_COMISARIA';
  c_en_investigacion  CONSTANT VARCHAR2(30) := 'EN_INVESTIGACION';
  c_intervencion      CONSTANT VARCHAR2(30) := 'INTERVENCION_PROGRAMADA';
  c_derivado          CONSTANT VARCHAR2(30) := 'DERIVADO_FISCALIA';
  c_archivado         CONSTANT VARCHAR2(30) := 'ARCHIVADO';
  c_resuelto          CONSTANT VARCHAR2(30) := 'RESUELTO';

  -- Minimum reason length for status changes and reassignments.
  c_min_reason_len    CONSTANT PLS_INTEGER := 10;

  -- Investigation module error codes.
  c_err_reason_required  CONSTANT PLS_INTEGER := -20020;
  c_err_bad_transition   CONSTANT PLS_INTEGER := -20021;
  c_err_not_found        CONSTANT PLS_INTEGER := -20022;
  c_err_no_assignment    CONSTANT PLS_INTEGER := -20023;
  c_err_bad_status       CONSTANT PLS_INTEGER := -20031;
  c_err_same_officer     CONSTANT PLS_INTEGER := -20032;
  c_err_reassign_reason  CONSTANT PLS_INTEGER := -20033;
  c_err_operation        CONSTANT PLS_INTEGER := -20040;
  c_err_active_assign    CONSTANT PLS_INTEGER := -20050;


  -- ---------------- Investigation statuses ----------------
  -- Whether the target status is reachable from the source status.
  FUNCTION is_valid_transition (p_from IN VARCHAR2, p_to IN VARCHAR2) RETURN BOOLEAN;

  -- Records a complaint's initial REGISTRADO status in the history.
  PROCEDURE log_initial_status (p_complaint_id IN NUMBER, p_officer_cip IN VARCHAR2,
                                p_reason IN VARCHAR2 DEFAULT 'Denuncia registrada en el sistema');

  -- Changes a complaint's status, validates the transition and records the history.
  PROCEDURE change_status (p_complaint_id IN NUMBER, p_new_status IN VARCHAR2,
                           p_officer_cip IN VARCHAR2, p_reason IN VARCHAR2,
                           p_observations IN VARCHAR2 DEFAULT NULL);

  -- Complaint status history (read-only, immutable).
  FUNCTION  get_status_history (p_complaint_id IN NUMBER) RETURN SYS_REFCURSOR;

  -- ---------------- Investigator assignment ----------------
  -- Assigns or reassigns the PRIMARY investigator and returns the assignment ID.
  FUNCTION  assign_investigator (p_complaint_id    IN NUMBER,
                                 p_officer_cip     IN VARCHAR2,
                                 p_assigned_by_cip IN VARCHAR2,
                                 p_reason          IN VARCHAR2 DEFAULT NULL) RETURN NUMBER;
  PROCEDURE close_assignment (p_assignment_id IN NUMBER, p_reason IN VARCHAR2);
  PROCEDURE update_assignment_reason (p_assignment_id IN NUMBER, p_reason IN VARCHAR2);
  -- Deletes closed assignments only.
  PROCEDURE delete_assignment (p_assignment_id IN NUMBER);
  FUNCTION  get_assignments (p_complaint_id IN NUMBER) RETURN SYS_REFCURSOR;
  -- Recalculates every officer's active_case_count from active assignments.
  PROCEDURE recalc_active_case_count;

  -- ---------------- Operations ----------------
  FUNCTION  create_operation (p_sector_id IN NUMBER, p_leader_cip IN VARCHAR2,
                              p_operation_type IN VARCHAR2, p_operation_date IN TIMESTAMP) RETURN NUMBER;
  PROCEDURE update_operation (p_operation_id IN NUMBER, p_sector_id IN NUMBER, p_leader_cip IN VARCHAR2,
                              p_operation_type IN VARCHAR2, p_operation_date IN TIMESTAMP);
  PROCEDURE update_operation_status (p_operation_id IN NUMBER, p_operation_status IN VARCHAR2,
                                     p_result_summary IN VARCHAR2 DEFAULT NULL);
  -- Deletes the operation and, by cascade, its linked complaints.
  PROCEDURE delete_operation (p_operation_id IN NUMBER);
  PROCEDURE link_complaint (p_operation_id IN NUMBER, p_complaint_id IN NUMBER,
                            p_assigned_officer_cip IN VARCHAR2, p_field_notes IN VARCHAR2 DEFAULT NULL);
  PROCEDURE unlink_complaint (p_operation_id IN NUMBER, p_complaint_id IN NUMBER);
  FUNCTION  get_operation (p_operation_id IN NUMBER) RETURN SYS_REFCURSOR;

  -- Registers an operation with several complaints in INTERVENCION_PROGRAMADA in the same sector.
  -- Each complaint goes to its PRIMARY investigator or, if none, to the leader.
  FUNCTION  register_operation (p_sector_id      IN NUMBER,
                                p_leader_cip     IN VARCHAR2,
                                p_operation_type IN VARCHAR2,
                                p_operation_date IN TIMESTAMP,
                                p_complaints     IN t_id_list) RETURN NUMBER;

END pkg_inv_mgmt;
/

CREATE OR REPLACE PACKAGE BODY pkg_inv_mgmt AS

  -- ===================================================================
  -- PRIVATE SUBPROGRAMS
  -- ===================================================================

  -- Locks the complaint and returns its current status.
  FUNCTION lock_complaint_status (p_complaint_id IN NUMBER) RETURN VARCHAR2 IS
    v_status tb_cpl_complaint.current_status%TYPE;
  BEGIN
    SELECT current_status INTO v_status
      FROM tb_cpl_complaint
     WHERE complaint_id = p_complaint_id
       FOR UPDATE;
    RETURN v_status;
  EXCEPTION WHEN NO_DATA_FOUND THEN
    RAISE_APPLICATION_ERROR(c_err_not_found, 'Denuncia inexistente: ' || p_complaint_id);
  END lock_complaint_status;

  -- Raises an error if the officer does not exist.
  PROCEDURE assert_officer_exists (p_cip IN VARCHAR2) IS
    v_cnt NUMBER;
  BEGIN
    SELECT COUNT(*) INTO v_cnt FROM tb_staff_officer WHERE officer_cip = p_cip;
    IF v_cnt = 0 THEN
      RAISE_APPLICATION_ERROR(c_err_not_found, 'Oficial inexistente: ' || p_cip);
    END IF;
  END assert_officer_exists;

  -- ===================================================================
  -- INVESTIGATION STATUSES
  -- ===================================================================
  FUNCTION is_valid_transition (p_from IN VARCHAR2, p_to IN VARCHAR2) RETURN BOOLEAN IS
  BEGIN
    IF p_from IS NULL THEN
      RETURN p_to = c_registrado;
    ELSIF p_from = c_registrado THEN
      RETURN p_to = c_validado;
    ELSIF p_from = c_validado THEN
      RETURN p_to = c_en_investigacion;
    ELSIF p_from = c_en_investigacion THEN
      RETURN p_to IN (c_intervencion, c_derivado, c_archivado, c_resuelto);
    ELSIF p_from = c_intervencion THEN
      RETURN p_to IN (c_en_investigacion, c_derivado, c_archivado, c_resuelto);
    ELSIF p_from = c_derivado THEN
      RETURN p_to IN (c_archivado, c_resuelto);
    END IF;
    RETURN FALSE;
  END is_valid_transition;

  PROCEDURE log_initial_status (p_complaint_id IN NUMBER, p_officer_cip IN VARCHAR2,
                                p_reason IN VARCHAR2 DEFAULT 'Denuncia registrada en el sistema') IS
  BEGIN
    assert_officer_exists(p_officer_cip);
    INSERT INTO tb_inv_status_history
      (history_id, complaint_id, officer_cip, previous_status, new_status, change_reason, observations)
    VALUES
      (seq_inv_status_history.NEXTVAL, p_complaint_id, p_officer_cip, NULL, c_registrado,
       SUBSTR(TRIM(p_reason), 1, 200), SUBSTR(TRIM(p_reason), 1, 400));
  END log_initial_status;

  PROCEDURE change_status (p_complaint_id IN NUMBER, p_new_status IN VARCHAR2,
                           p_officer_cip IN VARCHAR2, p_reason IN VARCHAR2,
                           p_observations IN VARCHAR2 DEFAULT NULL) IS
    v_prev tb_cpl_complaint.current_status%TYPE;
    v_cnt  NUMBER;
  BEGIN
    IF p_reason IS NULL OR LENGTH(TRIM(p_reason)) < c_min_reason_len THEN
      RAISE_APPLICATION_ERROR(c_err_reason_required,
        'Las observaciones/motivo son obligatorias (minimo ' || c_min_reason_len || ' caracteres).');
    END IF;

    assert_officer_exists(p_officer_cip);
    v_prev := lock_complaint_status(p_complaint_id);

    IF NOT is_valid_transition(v_prev, p_new_status) THEN
      RAISE_APPLICATION_ERROR(c_err_bad_transition,
        'Transicion no permitida: ' || NVL(v_prev,'(sin estado)') || ' -> ' || NVL(p_new_status,'NULL'));
    END IF;

    IF p_new_status = c_en_investigacion THEN
      SELECT COUNT(*) INTO v_cnt
        FROM tb_inv_assignment
       WHERE complaint_id = p_complaint_id AND role_type = 'PRIMARY' AND end_date IS NULL;
      IF v_cnt = 0 THEN
        RAISE_APPLICATION_ERROR(c_err_no_assignment,
          'No se puede pasar a EN_INVESTIGACION sin un investigador titular activo.');
      END IF;
    END IF;

    INSERT INTO tb_inv_status_history
      (history_id, complaint_id, officer_cip, previous_status, new_status, change_reason, observations)
    VALUES
      (seq_inv_status_history.NEXTVAL, p_complaint_id, p_officer_cip, v_prev, p_new_status,
       SUBSTR(TRIM(p_reason), 1, 200), SUBSTR(TRIM(NVL(p_observations, p_reason)), 1, 400));

    UPDATE tb_cpl_complaint
       SET current_status = p_new_status
     WHERE complaint_id = p_complaint_id;

    -- On closing the case, active assignments are closed and the slot is freed.
    IF p_new_status IN (c_archivado, c_resuelto) THEN
      UPDATE tb_inv_assignment
         SET end_date = SYSTIMESTAMP
       WHERE complaint_id = p_complaint_id AND end_date IS NULL;
    END IF;
  END change_status;

  FUNCTION get_status_history (p_complaint_id IN NUMBER) RETURN SYS_REFCURSOR IS
    v_rc SYS_REFCURSOR;
  BEGIN
    OPEN v_rc FOR
      SELECT history_id, complaint_id, officer_cip, previous_status, new_status,
             change_reason, observations, change_timestamp
        FROM tb_inv_status_history
       WHERE complaint_id = p_complaint_id
       ORDER BY change_timestamp, history_id;
    RETURN v_rc;
  END get_status_history;

  -- ===================================================================
  -- INVESTIGATOR ASSIGNMENT
  -- ===================================================================
  FUNCTION assign_investigator (p_complaint_id    IN NUMBER,
                                p_officer_cip     IN VARCHAR2,
                                p_assigned_by_cip IN VARCHAR2,
                                p_reason          IN VARCHAR2 DEFAULT NULL) RETURN NUMBER IS
    v_status    tb_cpl_complaint.current_status%TYPE;
    v_active_id NUMBER;
    v_active_by VARCHAR2(15);
    v_new_id    NUMBER;
  BEGIN
    SAVEPOINT sp_assign;

    IF p_officer_cip = p_assigned_by_cip THEN
      RAISE_APPLICATION_ERROR(c_err_same_officer,
        'El investigador no puede ser quien firma la asignacion.');
    END IF;
    assert_officer_exists(p_officer_cip);
    assert_officer_exists(p_assigned_by_cip);

    v_status := lock_complaint_status(p_complaint_id);
    IF v_status NOT IN (c_validado, c_en_investigacion, c_intervencion) THEN
      RAISE_APPLICATION_ERROR(c_err_bad_status,
        'Solo se asigna en VALIDADO_COMISARIA o se reasigna en EN_INVESTIGACION/INTERVENCION_PROGRAMADA. Estado actual: '
        || NVL(v_status,'NULL'));
    END IF;

    BEGIN
      SELECT assignment_id, officer_cip INTO v_active_id, v_active_by
        FROM tb_inv_assignment
       WHERE complaint_id = p_complaint_id AND role_type = 'PRIMARY' AND end_date IS NULL
         FOR UPDATE;
    EXCEPTION WHEN NO_DATA_FOUND THEN
      v_active_id := NULL;
    END;

    IF v_active_id IS NOT NULL THEN
      IF v_active_by = p_officer_cip THEN
        RAISE_APPLICATION_ERROR(c_err_same_officer, 'El oficial ya es el titular del caso.');
      END IF;
      IF p_reason IS NULL OR LENGTH(TRIM(p_reason)) < c_min_reason_len THEN
        RAISE_APPLICATION_ERROR(c_err_reassign_reason,
          'La reasignacion exige un motivo (minimo ' || c_min_reason_len || ' caracteres).');
      END IF;
      UPDATE tb_inv_assignment
         SET end_date = SYSTIMESTAMP,
             reassignment_reason = SUBSTR(TRIM(p_reason), 1, 200)
       WHERE assignment_id = v_active_id;
    ELSIF v_status <> c_validado THEN
      RAISE_APPLICATION_ERROR(c_err_bad_status,
        'El caso esta en ' || v_status || ' pero no tiene titular activo; revise la integridad.');
    END IF;

    -- Trigger trg_check_max_active_cases enforces the active case limit on this INSERT.
    INSERT INTO tb_inv_assignment (assignment_id, complaint_id, officer_cip, assigned_by_cip, role_type)
    VALUES (seq_inv_assignment.NEXTVAL, p_complaint_id, p_officer_cip, p_assigned_by_cip, 'PRIMARY')
    RETURNING assignment_id INTO v_new_id;

    IF v_status = c_validado THEN
      change_status(p_complaint_id, c_en_investigacion, p_assigned_by_cip,
                    'Asignacion de investigador titular CIP ' || p_officer_cip);
    END IF;

    RETURN v_new_id;
  EXCEPTION WHEN OTHERS THEN
    ROLLBACK TO sp_assign;
    RAISE;
  END assign_investigator;

  PROCEDURE close_assignment (p_assignment_id IN NUMBER, p_reason IN VARCHAR2) IS
  BEGIN
    UPDATE tb_inv_assignment
       SET end_date = SYSTIMESTAMP,
           reassignment_reason = SUBSTR(TRIM(p_reason), 1, 200)
     WHERE assignment_id = p_assignment_id AND end_date IS NULL;
    IF SQL%ROWCOUNT = 0 THEN
      RAISE_APPLICATION_ERROR(c_err_not_found, 'Asignacion inexistente o ya cerrada: ' || p_assignment_id);
    END IF;
  END close_assignment;

  PROCEDURE update_assignment_reason (p_assignment_id IN NUMBER, p_reason IN VARCHAR2) IS
  BEGIN
    UPDATE tb_inv_assignment
       SET reassignment_reason = SUBSTR(TRIM(p_reason), 1, 200)
     WHERE assignment_id = p_assignment_id;
    IF SQL%ROWCOUNT = 0 THEN
      RAISE_APPLICATION_ERROR(c_err_not_found, 'Asignacion inexistente: ' || p_assignment_id);
    END IF;
  END update_assignment_reason;

  PROCEDURE delete_assignment (p_assignment_id IN NUMBER) IS
    v_end tb_inv_assignment.end_date%TYPE;
  BEGIN
    BEGIN
      SELECT end_date INTO v_end FROM tb_inv_assignment WHERE assignment_id = p_assignment_id;
    EXCEPTION WHEN NO_DATA_FOUND THEN
      RAISE_APPLICATION_ERROR(c_err_not_found, 'Asignacion inexistente: ' || p_assignment_id);
    END;
    IF v_end IS NULL THEN
      RAISE_APPLICATION_ERROR(c_err_active_assign,
        'No se elimina una asignacion activa; cierrela primero con close_assignment.');
    END IF;
    DELETE FROM tb_inv_assignment WHERE assignment_id = p_assignment_id;
  END delete_assignment;

  FUNCTION get_assignments (p_complaint_id IN NUMBER) RETURN SYS_REFCURSOR IS
    v_rc SYS_REFCURSOR;
  BEGIN
    OPEN v_rc FOR
      SELECT assignment_id, complaint_id, officer_cip, assigned_by_cip,
             assignment_date, end_date, reassignment_reason, is_active, role_type
        FROM tb_inv_assignment
       WHERE complaint_id = p_complaint_id
       ORDER BY assignment_date;
    RETURN v_rc;
  END get_assignments;

  PROCEDURE recalc_active_case_count IS
  BEGIN
    UPDATE tb_staff_officer o
       SET active_case_count = (SELECT COUNT(*) FROM tb_inv_assignment a
                                 WHERE a.officer_cip = o.officer_cip AND a.end_date IS NULL);
  END recalc_active_case_count;

  -- ===================================================================
  -- OPERATIONS
  -- ===================================================================
  FUNCTION create_operation (p_sector_id IN NUMBER, p_leader_cip IN VARCHAR2,
                             p_operation_type IN VARCHAR2, p_operation_date IN TIMESTAMP) RETURN NUMBER IS
    v_id NUMBER;
  BEGIN
    INSERT INTO tb_ops_operation (operation_id, sector_id, leader_cip, operation_type, operation_date)
    VALUES (seq_ops_operation.NEXTVAL, p_sector_id, p_leader_cip, p_operation_type, p_operation_date)
    RETURNING operation_id INTO v_id;
    RETURN v_id;
  END create_operation;

  PROCEDURE update_operation (p_operation_id IN NUMBER, p_sector_id IN NUMBER, p_leader_cip IN VARCHAR2,
                              p_operation_type IN VARCHAR2, p_operation_date IN TIMESTAMP) IS
  BEGIN
    UPDATE tb_ops_operation
       SET sector_id = p_sector_id, leader_cip = p_leader_cip,
           operation_type = p_operation_type, operation_date = p_operation_date
     WHERE operation_id = p_operation_id;
    IF SQL%ROWCOUNT = 0 THEN
      RAISE_APPLICATION_ERROR(c_err_not_found, 'Operativo inexistente: ' || p_operation_id);
    END IF;
  END update_operation;

  PROCEDURE update_operation_status (p_operation_id IN NUMBER, p_operation_status IN VARCHAR2,
                                     p_result_summary IN VARCHAR2 DEFAULT NULL) IS
  BEGIN
    UPDATE tb_ops_operation
       SET operation_status = p_operation_status,
           result_summary   = NVL(SUBSTR(p_result_summary, 1, 400), result_summary)
     WHERE operation_id = p_operation_id;
    IF SQL%ROWCOUNT = 0 THEN
      RAISE_APPLICATION_ERROR(c_err_not_found, 'Operativo inexistente: ' || p_operation_id);
    END IF;
  END update_operation_status;

  PROCEDURE delete_operation (p_operation_id IN NUMBER) IS
  BEGIN
    DELETE FROM tb_ops_operation WHERE operation_id = p_operation_id;
    IF SQL%ROWCOUNT = 0 THEN
      RAISE_APPLICATION_ERROR(c_err_not_found, 'Operativo inexistente: ' || p_operation_id);
    END IF;
  END delete_operation;

  PROCEDURE link_complaint (p_operation_id IN NUMBER, p_complaint_id IN NUMBER,
                            p_assigned_officer_cip IN VARCHAR2, p_field_notes IN VARCHAR2 DEFAULT NULL) IS
  BEGIN
    INSERT INTO tb_ops_operation_complaint (operation_id, complaint_id, assigned_officer_cip, field_notes)
    VALUES (p_operation_id, p_complaint_id, p_assigned_officer_cip, SUBSTR(p_field_notes, 1, 250));
  END link_complaint;

  PROCEDURE unlink_complaint (p_operation_id IN NUMBER, p_complaint_id IN NUMBER) IS
  BEGIN
    DELETE FROM tb_ops_operation_complaint
     WHERE operation_id = p_operation_id AND complaint_id = p_complaint_id;
    IF SQL%ROWCOUNT = 0 THEN
      RAISE_APPLICATION_ERROR(c_err_not_found, 'La denuncia no esta vinculada al operativo.');
    END IF;
  END unlink_complaint;

  FUNCTION get_operation (p_operation_id IN NUMBER) RETURN SYS_REFCURSOR IS
    v_rc SYS_REFCURSOR;
  BEGIN
    OPEN v_rc FOR
      SELECT o.operation_id, o.sector_id, o.leader_cip, o.operation_type, o.operation_date,
             o.operation_status, o.result_summary,
             (SELECT COUNT(*) FROM tb_ops_operation_complaint c WHERE c.operation_id = o.operation_id) AS n_complaints
        FROM tb_ops_operation o
       WHERE o.operation_id = p_operation_id;
    RETURN v_rc;
  END get_operation;

  FUNCTION register_operation (p_sector_id      IN NUMBER,
                               p_leader_cip     IN VARCHAR2,
                               p_operation_type IN VARCHAR2,
                               p_operation_date IN TIMESTAMP,
                               p_complaints     IN t_id_list) RETURN NUMBER IS
    v_op      NUMBER;
    v_status  tb_cpl_complaint.current_status%TYPE;
    v_sector  tb_cpl_complaint.sector_id%TYPE;
    v_officer tb_inv_assignment.officer_cip%TYPE;
  BEGIN
    SAVEPOINT sp_register_op;

    IF p_complaints IS NULL OR p_complaints.COUNT = 0 THEN
      RAISE_APPLICATION_ERROR(c_err_operation, 'El operativo debe vincular al menos una denuncia.');
    END IF;

    FOR i IN 1 .. p_complaints.COUNT LOOP
      BEGIN
        SELECT current_status, sector_id INTO v_status, v_sector
          FROM tb_cpl_complaint WHERE complaint_id = p_complaints(i);
      EXCEPTION WHEN NO_DATA_FOUND THEN
        RAISE_APPLICATION_ERROR(c_err_not_found, 'Denuncia inexistente: ' || p_complaints(i));
      END;
      IF v_status <> c_intervencion THEN
        RAISE_APPLICATION_ERROR(c_err_operation,
          'La denuncia ' || p_complaints(i) || ' debe estar en INTERVENCION_PROGRAMADA (actual: ' || v_status || ').');
      END IF;
      IF v_sector <> p_sector_id THEN
        RAISE_APPLICATION_ERROR(c_err_operation,
          'La denuncia ' || p_complaints(i) || ' pertenece a otro sector.');
      END IF;
    END LOOP;

    v_op := create_operation(p_sector_id, p_leader_cip, p_operation_type, p_operation_date);

    FOR i IN 1 .. p_complaints.COUNT LOOP
      BEGIN
        SELECT officer_cip INTO v_officer
          FROM tb_inv_assignment
         WHERE complaint_id = p_complaints(i) AND role_type = 'PRIMARY' AND end_date IS NULL;
      EXCEPTION WHEN NO_DATA_FOUND THEN
        v_officer := p_leader_cip;
      END;
      link_complaint(v_op, p_complaints(i), v_officer);
    END LOOP;

    RETURN v_op;
  EXCEPTION WHEN OTHERS THEN
    ROLLBACK TO sp_register_op;
    RAISE;
  END register_operation;

END pkg_inv_mgmt;
/
SHOW ERRORS PACKAGE pkg_inv_mgmt
SHOW ERRORS PACKAGE BODY pkg_inv_mgmt

