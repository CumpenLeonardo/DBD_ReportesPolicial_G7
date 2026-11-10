-- =============================================================================
-- 10_schema.sql
-- Estructura de la base de datos: secuencias, tablas, restricciones, índices y triggers.
-- =============================================================================

-- =============================================================================
-- SECCION 1: Moneda, organización, territorio y personal
-- =============================================================================

-- Secuencias para los IDs automáticos. Empiezan por encima de los IDs de la carga
CREATE SEQUENCE seq_cfg_currency START WITH 10   INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE seq_org_division START WITH 100  INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE seq_org_station  START WITH 100  INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE seq_terr_sector  START WITH 1000 INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE seq_staff_rank   START WITH 10   INCREMENT BY 1 NOCACHE;

-- Monedas y su tasa de conversión a soles (PEN).
CREATE TABLE tb_cfg_currency (
  currency_id       NUMBER(3)    NOT NULL,
  currency_code     VARCHAR2(3)  NOT NULL,
  currency_name     VARCHAR2(50) NOT NULL,
  exchange_rate_pen NUMBER(10,4) NOT NULL,
  CONSTRAINT pk_cfg_currency      PRIMARY KEY (currency_id),
  CONSTRAINT uk_cfg_currency_code UNIQUE (currency_code),
  CONSTRAINT ck_cfg_currency_rate CHECK (exchange_rate_pen > 0)
) TABLESPACE ts_geo_data;

-- División policial: agrupa comisarías.
CREATE TABLE tb_org_division (
  division_id   NUMBER(5)     NOT NULL,
  division_name VARCHAR2(100) NOT NULL,
  region_name   VARCHAR2(60)  NOT NULL,
  CONSTRAINT pk_org_division PRIMARY KEY (division_id)
) TABLESPACE ts_geo_data;

-- Comisaría: pertenece a una división y es la sede de adscripción de los efectivos.
CREATE TABLE tb_org_station (
  station_id   NUMBER(5)     NOT NULL,
  division_id  NUMBER(5)     NOT NULL,
  station_name VARCHAR2(100) NOT NULL,
  address      VARCHAR2(200) NOT NULL,
  CONSTRAINT pk_org_station PRIMARY KEY (station_id),
  CONSTRAINT fk_org_station_division FOREIGN KEY (division_id) REFERENCES tb_org_division (division_id)
) TABLESPACE ts_geo_data;

-- Sector vecinal. Se define por una caja de coordenadas (filtro rápido)
-- y por un polígono de Oracle Spatial (verificación exacta).
CREATE TABLE tb_terr_sector (
  sector_id    NUMBER(8)     NOT NULL,
  station_id   NUMBER(5)     NOT NULL,
  sector_name  VARCHAR2(100) NOT NULL,
  min_lat      NUMBER(10,7)  NOT NULL,
  max_lat      NUMBER(10,7)  NOT NULL,
  min_lon      NUMBER(10,7)  NOT NULL,
  max_lon      NUMBER(10,7)  NOT NULL,
  polygon_area SDO_GEOMETRY,
  CONSTRAINT pk_terr_sector PRIMARY KEY (sector_id),
  CONSTRAINT fk_terr_sector_station FOREIGN KEY (station_id) REFERENCES tb_org_station (station_id),
  CONSTRAINT ck_terr_sector_lat CHECK (min_lat < max_lat),
  CONSTRAINT ck_terr_sector_lon CHECK (min_lon < max_lon)
) TABLESPACE ts_geo_data;

-- Grados policiales. Un hierarchy_level menor corresponde a un grado superior.
CREATE TABLE tb_staff_rank (
  rank_id         NUMBER(3)    NOT NULL,
  rank_name       VARCHAR2(50) NOT NULL,
  hierarchy_level NUMBER(2)    NOT NULL,
  CONSTRAINT pk_staff_rank      PRIMARY KEY (rank_id),
  CONSTRAINT uk_staff_rank_name UNIQUE (rank_name)
) TABLESPACE ts_geo_data;

-- Efectivo policial, identificado por su CIP. supervisor_cip apunta a otro efectivo.
CREATE TABLE tb_staff_officer (
  officer_cip       VARCHAR2(15) NOT NULL,
  first_name        VARCHAR2(60) NOT NULL,
  last_name         VARCHAR2(60) NOT NULL,
  rank_id           NUMBER(3)    NOT NULL,
  station_id        NUMBER(5)    NOT NULL,
  supervisor_cip    VARCHAR2(15),
  specialty         VARCHAR2(60) NOT NULL,
  active_case_count NUMBER(4)    DEFAULT 0 NOT NULL,
  CONSTRAINT pk_staff_officer PRIMARY KEY (officer_cip),
  CONSTRAINT fk_staff_officer_rank    FOREIGN KEY (rank_id)        REFERENCES tb_staff_rank (rank_id),
  CONSTRAINT fk_staff_officer_station FOREIGN KEY (station_id)     REFERENCES tb_org_station (station_id),
  CONSTRAINT fk_staff_officer_super   FOREIGN KEY (supervisor_cip) REFERENCES tb_staff_officer (officer_cip),
  CONSTRAINT ck_staff_officer_super   CHECK (supervisor_cip IS NULL OR supervisor_cip <> officer_cip),
  CONSTRAINT ck_staff_officer_spec    CHECK (specialty IN ('INVESTIGADOR_CRIMINAL', 'ORDEN_PUBLICO', 'INTELIGENCIA', 'ADMINISTRACION', 'TIC', 'SEGURIDAD_INTEGRAL', 'CRIMINALISTICA')),
  CONSTRAINT ck_staff_officer_cases   CHECK (active_case_count >= 0)
) TABLESPACE ts_geo_data;

-- Índices sobre llaves foráneas.
CREATE INDEX idx_org_station_division  ON tb_org_station (division_id) TABLESPACE ts_geo_data;
CREATE INDEX idx_terr_sector_station   ON tb_terr_sector (station_id) TABLESPACE ts_geo_data;
CREATE INDEX idx_staff_officer_rank    ON tb_staff_officer (rank_id) TABLESPACE ts_geo_data;
CREATE INDEX idx_staff_officer_station ON tb_staff_officer (station_id) TABLESPACE ts_geo_data;
CREATE INDEX idx_staff_officer_super   ON tb_staff_officer (supervisor_cip) TABLESPACE ts_geo_data;

-- Metadata espacial del polígono del sector (requerida antes de crear el índice espacial).
INSERT INTO user_sdo_geom_metadata (table_name, column_name, diminfo, srid)
VALUES ('TB_TERR_SECTOR', 'POLYGON_AREA',
        SDO_DIM_ARRAY(SDO_DIM_ELEMENT('LONGITUDE', -180, 180, 0.005),
                      SDO_DIM_ELEMENT('LATITUDE',   -90,  90, 0.005)),
        4326);
COMMIT;

-- Índice espacial para buscar el sector que contiene un punto GPS.
CREATE INDEX idx_terr_sector_polygon ON tb_terr_sector (polygon_area)
  INDEXTYPE IS MDSYS.SPATIAL_INDEX_V2
  PARAMETERS ('tablespace=ts_geo_data');

-- =============================================================================
-- SECCION 2: Juntas vecinales
-- =============================================================================

CREATE SEQUENCE seq_com_channel START WITH 10  INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE seq_com_assoc   START WITH 100 INCREMENT BY 1 NOCACHE;

-- Canal formal de comunicación entre una junta vecinal y la policía.
CREATE TABLE tb_com_channel (
  channel_id      NUMBER(4)    NOT NULL,
  channel_type    VARCHAR2(40) NOT NULL,
  channel_contact VARCHAR2(100),
  CONSTRAINT pk_com_channel PRIMARY KEY (channel_id)
) TABLESPACE ts_geo_data;

-- Junta vecinal: pertenece a un sector y tiene un coordinador y un canal autorizado.
CREATE TABLE tb_com_neighborhood_assoc (
  assoc_id              NUMBER(6)     NOT NULL,
  sector_id             NUMBER(8)     NOT NULL,
  assoc_name            VARCHAR2(100) NOT NULL,
  coordinator_name      VARCHAR2(120) NOT NULL,
  coordinator_phone     VARCHAR2(20)  NOT NULL,
  authorized_channel_id NUMBER(4)     NOT NULL,
  CONSTRAINT pk_com_assoc PRIMARY KEY (assoc_id),
  CONSTRAINT fk_com_assoc_sector  FOREIGN KEY (sector_id) REFERENCES tb_terr_sector (sector_id),
  CONSTRAINT fk_com_assoc_channel FOREIGN KEY (authorized_channel_id) REFERENCES tb_com_channel (channel_id)
) TABLESPACE ts_geo_data;

-- Índices sobre llaves foráneas.
CREATE INDEX idx_com_assoc_sector  ON tb_com_neighborhood_assoc (sector_id) TABLESPACE ts_geo_data;
CREATE INDEX idx_com_assoc_channel ON tb_com_neighborhood_assoc (authorized_channel_id) TABLESPACE ts_geo_data;

-- =============================================================================
-- SECCION 3: Denuncias, modalidades, establecimientos, denunciantes y evidencias
-- =============================================================================

-- Secuencias (genenran las PK): 
CREATE SEQUENCE seq_cpl_modality      START WITH 1      INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE seq_cpl_establishment START WITH 1000   INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE seq_cpl_reporter      START WITH 1000   INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE seq_cpl_protection    START WITH 5000   INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE seq_cpl_complaint     START WITH 100001 INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE seq_cpl_evidence      START WITH 1      INCREMENT BY 1 NOCACHE;

-- Catálogo de modalidades extorsivas.
CREATE TABLE tb_cpl_modality (
  modality_id    NUMBER(3)
                 CONSTRAINT pk_cpl_modality PRIMARY KEY,
  modality_name  VARCHAR2(80)
                 CONSTRAINT nn_cpl_modality_name NOT NULL,
  severity_level VARCHAR2(20)
                 CONSTRAINT nn_cpl_modality_sev NOT NULL,
  CONSTRAINT uk_cpl_modality_name UNIQUE (modality_name),
  CONSTRAINT chk_cpl_modality_sev CHECK (severity_level IN ('HIGH','CRITICAL'))
) TABLESPACE ts_geo_data;

-- Comercios o paraderos afectados.
CREATE TABLE tb_cpl_establishment (
  establishment_id   NUMBER(10)
                     CONSTRAINT pk_cpl_establishment PRIMARY KEY,
  establishment_name VARCHAR2(120)
                     CONSTRAINT nn_cpl_estab_name NOT NULL,
  establishment_type VARCHAR2(40)
                     CONSTRAINT nn_cpl_estab_type NOT NULL,
  address            VARCHAR2(200)
                     CONSTRAINT nn_cpl_estab_address NOT NULL,
  latitude           NUMBER(10,7)
                     CONSTRAINT nn_cpl_estab_lat NOT NULL,
  longitude          NUMBER(10,7)
                     CONSTRAINT nn_cpl_estab_lon NOT NULL,
  location_geom      SDO_GEOMETRY,
  CONSTRAINT chk_cpl_estab_lat CHECK (latitude  BETWEEN -90  AND 90),
  CONSTRAINT chk_cpl_estab_lon CHECK (longitude BETWEEN -180 AND 180)
) TABLESPACE ts_geo_data;

-- Datos reales del denunciante.
CREATE TABLE tb_cpl_reporter (
  id_reporter          NUMBER(10)
                       CONSTRAINT pk_cpl_reporter PRIMARY KEY,
  personal_document_id VARCHAR2(20)
                       CONSTRAINT nn_cpl_rep_doc NOT NULL,
  first_name           VARCHAR2(50)
                       CONSTRAINT nn_cpl_rep_fname NOT NULL,
  last_name            VARCHAR2(50)
                       CONSTRAINT nn_cpl_rep_lname NOT NULL,
  gender               CHAR(1)
                       CONSTRAINT nn_cpl_rep_gender NOT NULL,
  address              VARCHAR2(200)
                       CONSTRAINT nn_cpl_rep_address NOT NULL,
  phone_number         VARCHAR2(15),
  email                VARCHAR2(100),
  CONSTRAINT uk_cpl_rep_doc     UNIQUE (personal_document_id),
  CONSTRAINT chk_cpl_rep_gender CHECK (gender IN ('H','M')),
  CONSTRAINT chk_cpl_rep_contact CHECK (email IS NOT NULL OR phone_number IS NOT NULL)
) TABLESPACE ts_geo_data;

-- Código protegido del denunciante anónimo: la identidad real queda aquí
-- y la denuncia solo referencia protected_code.
CREATE TABLE tb_cpl_complaint_protection (
  protected_code      NUMBER(10)
                      CONSTRAINT pk_cpl_protection PRIMARY KEY,
  id_reporter         NUMBER(10)
                      CONSTRAINT nn_cpl_prot_reporter NOT NULL,
  date_approved       TIMESTAMP DEFAULT SYSTIMESTAMP
                      CONSTRAINT nn_cpl_prot_date NOT NULL,
  approved_by_officer VARCHAR2(15)
                      CONSTRAINT nn_cpl_prot_officer NOT NULL,
  CONSTRAINT fk_cpl_prot_reporter FOREIGN KEY (id_reporter)
             REFERENCES tb_cpl_reporter (id_reporter),
  CONSTRAINT fk_cpl_prot_officer  FOREIGN KEY (approved_by_officer)
             REFERENCES tb_staff_officer (officer_cip)
) TABLESPACE ts_geo_data;

-- Denuncias y alertas. Una denuncia es firmada (id_reporter) o anónima (protected_code), nunca ambas.
CREATE TABLE tb_cpl_complaint (
  complaint_id       NUMBER(12)
                     CONSTRAINT pk_cpl_complaint PRIMARY KEY,
  sector_id          NUMBER(8)
                     CONSTRAINT nn_cpl_cmp_sector NOT NULL,
  modality_id        NUMBER(3)
                     CONSTRAINT nn_cpl_cmp_modality NOT NULL,
  establishment_id   NUMBER(10),
  assoc_id           NUMBER(6),
  incident_date      TIMESTAMP
                     CONSTRAINT nn_cpl_cmp_incdate NOT NULL,
  registration_date  TIMESTAMP DEFAULT SYSTIMESTAMP
                     CONSTRAINT nn_cpl_cmp_regdate NOT NULL,
  is_anonymous       CHAR(1)
                     CONSTRAINT nn_cpl_cmp_anon NOT NULL,
  currency_id        NUMBER(3) DEFAULT 1
                     CONSTRAINT nn_cpl_cmp_currency NOT NULL,
  amount_original    NUMBER(12,2) DEFAULT 0
                     CONSTRAINT nn_cpl_cmp_amount NOT NULL,
  amount_pen         NUMBER(12,2) DEFAULT 0
                     CONSTRAINT nn_cpl_cmp_amount_pen NOT NULL,
  payment_frequency  VARCHAR2(30),
  extortionist_alias VARCHAR2(200),
  current_status     VARCHAR2(30) DEFAULT 'REGISTRADO'
                     CONSTRAINT nn_cpl_cmp_status NOT NULL,
  latitude           NUMBER(10,7)
                     CONSTRAINT nn_cpl_cmp_lat NOT NULL,
  longitude          NUMBER(10,7)
                     CONSTRAINT nn_cpl_cmp_lon NOT NULL,
  incident_address   VARCHAR2(200)
                     CONSTRAINT nn_cpl_cmp_address NOT NULL,
  incident_location  SDO_GEOMETRY,
  id_reporter        NUMBER(10),
  protected_code     NUMBER(10),

  CONSTRAINT fk_cpl_cmp_sector     FOREIGN KEY (sector_id)
             REFERENCES tb_terr_sector (sector_id),
  CONSTRAINT fk_cpl_cmp_modality   FOREIGN KEY (modality_id)
             REFERENCES tb_cpl_modality (modality_id),
  CONSTRAINT fk_cpl_cmp_estab      FOREIGN KEY (establishment_id)
             REFERENCES tb_cpl_establishment (establishment_id),
  CONSTRAINT fk_cpl_cmp_assoc      FOREIGN KEY (assoc_id)
             REFERENCES tb_com_neighborhood_assoc (assoc_id),
  CONSTRAINT fk_cpl_cmp_currency   FOREIGN KEY (currency_id)
             REFERENCES tb_cfg_currency (currency_id),
  CONSTRAINT fk_cpl_cmp_reporter   FOREIGN KEY (id_reporter)
             REFERENCES tb_cpl_reporter (id_reporter),
  CONSTRAINT fk_cpl_cmp_protection FOREIGN KEY (protected_code)
             REFERENCES tb_cpl_complaint_protection (protected_code),

  CONSTRAINT chk_cpl_cmp_anon      CHECK (is_anonymous IN ('Y','N')),
  CONSTRAINT chk_cpl_cmp_amount    CHECK (amount_original >= 0),
  CONSTRAINT chk_cpl_cmp_frequency CHECK (payment_frequency IN
             ('DIARIAMENTE','SEMANALMENTE','MENSUALMENTE','UNA VEZ')),
  CONSTRAINT chk_cpl_cmp_status    CHECK (current_status IN
             ('REGISTRADO','VALIDADO_COMISARIA','EN_INVESTIGACION','INTERVENCION_PROGRAMADA',
              'DERIVADO_FISCALIA','ARCHIVADO','RESUELTO')),
  CONSTRAINT chk_cpl_cmp_lat       CHECK (latitude  BETWEEN -90  AND 90),
  CONSTRAINT chk_cpl_cmp_lon       CHECK (longitude BETWEEN -180 AND 180),
  CONSTRAINT chk_cpl_cmp_dates     CHECK (incident_date <= registration_date),
  CONSTRAINT chk_cpl_cmp_identity  CHECK (
       (is_anonymous = 'N' AND id_reporter IS NOT NULL AND protected_code IS NULL)
    OR (is_anonymous = 'Y' AND id_reporter IS NULL     AND protected_code IS NOT NULL)
  )
) TABLESPACE ts_geo_data;

-- Evidencias multimedia asociadas a una denuncia.
CREATE TABLE tb_cpl_digital_evidence (
  evidence_id     NUMBER(12)
                  CONSTRAINT pk_cpl_evidence PRIMARY KEY,
  complaint_id    NUMBER(12)
                  CONSTRAINT nn_cpl_ev_complaint NOT NULL,
  uploaded_by_cip VARCHAR2(15)
                  CONSTRAINT nn_cpl_ev_officer NOT NULL,
  evidence_type   VARCHAR2(40)
                  CONSTRAINT nn_cpl_ev_type NOT NULL,
  file_path       VARCHAR2(250)
                  CONSTRAINT nn_cpl_ev_path NOT NULL,
  description_ev  VARCHAR2(200)
                  CONSTRAINT nn_cpl_ev_desc NOT NULL,
  upload_date     TIMESTAMP DEFAULT SYSTIMESTAMP
                  CONSTRAINT nn_cpl_ev_date NOT NULL,
  CONSTRAINT fk_cpl_ev_complaint FOREIGN KEY (complaint_id)
             REFERENCES tb_cpl_complaint (complaint_id),
  CONSTRAINT fk_cpl_ev_officer   FOREIGN KEY (uploaded_by_cip)
             REFERENCES tb_staff_officer (officer_cip),
  CONSTRAINT chk_cpl_ev_type CHECK (evidence_type IN
             ('GRABACION DE AUDIO','SCREENSHOT','VIDEO DE SEGURIDAD','FOTO'))
) TABLESPACE ts_geo_data;

-- Índices sobre llaves foráneas.
CREATE INDEX idx_cpl_prot_reporter ON tb_cpl_complaint_protection (id_reporter) TABLESPACE ts_geo_data;
CREATE INDEX idx_cpl_prot_officer  ON tb_cpl_complaint_protection (approved_by_officer) TABLESPACE ts_geo_data;
CREATE INDEX idx_cpl_cmp_sector    ON tb_cpl_complaint (sector_id) TABLESPACE ts_geo_data;
CREATE INDEX idx_cpl_cmp_modality  ON tb_cpl_complaint (modality_id) TABLESPACE ts_geo_data;
CREATE INDEX idx_cpl_cmp_estab     ON tb_cpl_complaint (establishment_id) TABLESPACE ts_geo_data;
CREATE INDEX idx_cpl_cmp_assoc     ON tb_cpl_complaint (assoc_id) TABLESPACE ts_geo_data;
CREATE INDEX idx_cpl_cmp_currency  ON tb_cpl_complaint (currency_id) TABLESPACE ts_geo_data;
CREATE INDEX idx_cpl_cmp_reporter  ON tb_cpl_complaint (id_reporter) TABLESPACE ts_geo_data;
CREATE INDEX idx_cpl_cmp_protcode  ON tb_cpl_complaint (protected_code) TABLESPACE ts_geo_data;
CREATE INDEX idx_cpl_ev_complaint  ON tb_cpl_digital_evidence (complaint_id) TABLESPACE ts_geo_data;
CREATE INDEX idx_cpl_ev_officer    ON tb_cpl_digital_evidence (uploaded_by_cip) TABLESPACE ts_geo_data;

-- Índice por fecha del incidente para los reportes mensuales.
CREATE INDEX idx_cpl_cmp_incdate   ON tb_cpl_complaint (incident_date) TABLESPACE ts_geo_data;

-- Metadata espacial de las columnas de ubicación (requerida antes de crear los índices espaciales).
INSERT INTO user_sdo_geom_metadata (table_name, column_name, diminfo, srid)
VALUES ('TB_CPL_ESTABLISHMENT', 'LOCATION_GEOM',
        SDO_DIM_ARRAY(SDO_DIM_ELEMENT('LONGITUDE', -180, 180, 0.05),
                      SDO_DIM_ELEMENT('LATITUDE',   -90,  90, 0.05)),
        4326);

INSERT INTO user_sdo_geom_metadata (table_name, column_name, diminfo, srid)
VALUES ('TB_CPL_COMPLAINT', 'INCIDENT_LOCATION',
        SDO_DIM_ARRAY(SDO_DIM_ELEMENT('LONGITUDE', -180, 180, 0.05),
                      SDO_DIM_ELEMENT('LATITUDE',   -90,  90, 0.05)),
        4326);
COMMIT;

-- Índices espaciales sobre las ubicaciones (solo almacenan puntos).
CREATE INDEX sidx_cpl_estab_geom ON tb_cpl_establishment (location_geom)
  INDEXTYPE IS MDSYS.SPATIAL_INDEX_V2
  PARAMETERS ('layer_gtype=POINT tablespace=ts_geo_data');

CREATE INDEX sidx_cpl_cmp_geom ON tb_cpl_complaint (incident_location)
  INDEXTYPE IS MDSYS.SPATIAL_INDEX_V2
  PARAMETERS ('layer_gtype=POINT tablespace=ts_geo_data');

-- =============================================================================
-- SECCION 4: Investigación y operativos
-- =============================================================================
-- Secuencias que generan las llaves primarias.
CREATE SEQUENCE SEQ_INV_ASSIGNMENT     START WITH 1 INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE SEQ_INV_STATUS_HISTORY START WITH 1 INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE SEQ_OPS_OPERATION      START WITH 1 INCREMENT BY 1 NOCACHE;

-- Asignaciones de investigadores a denuncias (historial de reasignaciones).
-- Solo puede haber un investigador PRIMARY activo por denuncia.
CREATE TABLE tb_inv_assignment (
  assignment_id       NUMBER(12),
  complaint_id        NUMBER(12)   NOT NULL,
  officer_cip         VARCHAR2(15) NOT NULL,
  assigned_by_cip     VARCHAR2(15) NOT NULL,
  assignment_date     TIMESTAMP    DEFAULT SYSTIMESTAMP NOT NULL,
  end_date            TIMESTAMP,
  reassignment_reason VARCHAR2(200),
  is_active           CHAR(1)      DEFAULT 'Y' NOT NULL,
  role_type           VARCHAR2(20) DEFAULT 'PRIMARY' NOT NULL,
  CONSTRAINT pk_inv_assignment   PRIMARY KEY (assignment_id),
  CONSTRAINT fk_invasg_complaint FOREIGN KEY (complaint_id)
      REFERENCES tb_cpl_complaint (complaint_id),
  CONSTRAINT fk_invasg_officer   FOREIGN KEY (officer_cip)
      REFERENCES tb_staff_officer (officer_cip),
  CONSTRAINT fk_invasg_assigner  FOREIGN KEY (assigned_by_cip)
      REFERENCES tb_staff_officer (officer_cip),
  CONSTRAINT ck_invasg_diff_cip  CHECK (officer_cip <> assigned_by_cip),
  CONSTRAINT ck_invasg_dates     CHECK (end_date IS NULL OR end_date >= TRUNC(assignment_date)),
  CONSTRAINT ck_invasg_role      CHECK (role_type IN ('PRIMARY', 'SUPPORT')),
  CONSTRAINT ck_invasg_active    CHECK (is_active IN ('Y', 'N'))
) TABLESPACE ts_geo_data;

-- Historial inmutable de estados de las denuncias.
CREATE TABLE tb_inv_status_history (
  history_id       NUMBER(14),
  complaint_id     NUMBER(12)    NOT NULL,
  officer_cip      VARCHAR2(15)  NOT NULL,
  previous_status  VARCHAR2(30),
  new_status       VARCHAR2(30)  NOT NULL,
  change_reason    VARCHAR2(200) NOT NULL,
  observations     VARCHAR2(400) NOT NULL,
  change_timestamp TIMESTAMP     DEFAULT SYSTIMESTAMP NOT NULL,
  CONSTRAINT pk_inv_status_history PRIMARY KEY (history_id),
  CONSTRAINT fk_invhst_complaint   FOREIGN KEY (complaint_id)
      REFERENCES tb_cpl_complaint (complaint_id),
  CONSTRAINT fk_invhst_officer     FOREIGN KEY (officer_cip)
      REFERENCES tb_staff_officer (officer_cip),
  CONSTRAINT ck_invhst_new_status  CHECK (new_status IN
      ('REGISTRADO','VALIDADO_COMISARIA','EN_INVESTIGACION',
       'INTERVENCION_PROGRAMADA','DERIVADO_FISCALIA','ARCHIVADO','RESUELTO')),
  CONSTRAINT ck_invhst_prev_status CHECK (previous_status IS NULL OR previous_status IN
      ('REGISTRADO','VALIDADO_COMISARIA','EN_INVESTIGACION',
       'INTERVENCION_PROGRAMADA','DERIVADO_FISCALIA','ARCHIVADO','RESUELTO')),
  CONSTRAINT ck_invhst_diff_status CHECK (previous_status IS NULL OR previous_status <> new_status),
  CONSTRAINT ck_invhst_reason      CHECK (TRIM(change_reason) IS NOT NULL)
) TABLESPACE ts_geo_data;

-- Operativos policiales en un sector, a cargo de un líder.
CREATE TABLE tb_ops_operation (
  operation_id     NUMBER(10),
  sector_id        NUMBER(8)     NOT NULL,
  leader_cip       VARCHAR2(15)  NOT NULL,
  operation_type   VARCHAR2(40)  NOT NULL,
  operation_date   TIMESTAMP     NOT NULL,
  operation_status VARCHAR2(20)  DEFAULT 'PROGRAMADO' NOT NULL,
  result_summary   VARCHAR2(400),
  CONSTRAINT pk_ops_operation  PRIMARY KEY (operation_id),
  CONSTRAINT fk_opsop_sector   FOREIGN KEY (sector_id)
      REFERENCES tb_terr_sector (sector_id),
  CONSTRAINT fk_opsop_leader   FOREIGN KEY (leader_cip)
      REFERENCES tb_staff_officer (officer_cip),
  CONSTRAINT ck_opsop_status   CHECK (operation_status IN
      ('PROGRAMADO', 'CANCELADO', 'EJECUTADO', 'RETRASADO', 'EN EJECUCION'))
) TABLESPACE ts_geo_data;

-- Relación N:M entre operativos y denuncias. Al borrar un operativo se borran sus vínculos.
CREATE TABLE tb_ops_operation_complaint (
  operation_id         NUMBER(10)   NOT NULL,
  complaint_id         NUMBER(12)   NOT NULL,
  assigned_officer_cip VARCHAR2(15) NOT NULL,
  field_notes          VARCHAR2(250),
  CONSTRAINT pk_ops_operation_complaint PRIMARY KEY (operation_id, complaint_id),
  CONSTRAINT fk_opsoc_operation FOREIGN KEY (operation_id)
      REFERENCES tb_ops_operation (operation_id) ON DELETE CASCADE,
  CONSTRAINT fk_opsoc_complaint FOREIGN KEY (complaint_id)
      REFERENCES tb_cpl_complaint (complaint_id),
  CONSTRAINT fk_opsoc_officer   FOREIGN KEY (assigned_officer_cip)
      REFERENCES tb_staff_officer (officer_cip)
) TABLESPACE ts_geo_data;

-- Índice único: un solo investigador PRIMARY activo por denuncia.
-- Si la asignación está cerrada o no es PRIMARY, la expresión es NULL y no entra al índice.
CREATE UNIQUE INDEX ux_invasg_active_per_complaint
  ON tb_inv_assignment (CASE WHEN role_type = 'PRIMARY' AND end_date IS NULL THEN complaint_id END)
  TABLESPACE ts_geo_data;

-- Índices sobre llaves foráneas.
CREATE INDEX ix_invasg_officer   ON tb_inv_assignment (officer_cip, end_date) TABLESPACE ts_geo_data;
CREATE INDEX ix_invasg_complaint ON tb_inv_assignment (complaint_id) TABLESPACE ts_geo_data;
CREATE INDEX ix_invasg_assigner  ON tb_inv_assignment (assigned_by_cip) TABLESPACE ts_geo_data;
CREATE INDEX ix_invhst_complaint ON tb_inv_status_history (complaint_id, change_timestamp) TABLESPACE ts_geo_data;
CREATE INDEX ix_invhst_officer   ON tb_inv_status_history (officer_cip) TABLESPACE ts_geo_data;
CREATE INDEX ix_opsop_sector     ON tb_ops_operation (sector_id) TABLESPACE ts_geo_data;
CREATE INDEX ix_opsop_leader     ON tb_ops_operation (leader_cip) TABLESPACE ts_geo_data;
CREATE INDEX ix_opsoc_complaint  ON tb_ops_operation_complaint (complaint_id) TABLESPACE ts_geo_data;
CREATE INDEX ix_opsoc_officer    ON tb_ops_operation_complaint (assigned_officer_cip) TABLESPACE ts_geo_data;

-- =============================================================================
-- SECCION 5: Triggers de denuncias
-- =============================================================================

-- Genera location_geom (punto WGS 84) a partir de la latitud y longitud del establecimiento.
CREATE OR REPLACE TRIGGER trg_cpl_estab_geom
BEFORE INSERT OR UPDATE OF latitude, longitude ON tb_cpl_establishment
FOR EACH ROW
BEGIN
  :NEW.location_geom := SDO_GEOMETRY(
        2001,
        4326,
        SDO_POINT_TYPE(:NEW.longitude, :NEW.latitude, NULL),
        NULL, NULL);
END;
/

-- Genera incident_location (punto WGS 84) a partir de la latitud y longitud de la denuncia.
CREATE OR REPLACE TRIGGER trg_cpl_complaint_geom
BEFORE INSERT OR UPDATE OF latitude, longitude ON tb_cpl_complaint
FOR EACH ROW
BEGIN
  :NEW.incident_location := SDO_GEOMETRY(
        2001,
        4326,
        SDO_POINT_TYPE(:NEW.longitude, :NEW.latitude, NULL),
        NULL, NULL);
END;
/

-- Calcula amount_pen = amount_original x tasa de la moneda al insertar la denuncia
-- o al cambiar el monto o la moneda. No se recalcula si solo cambia la tasa.
CREATE OR REPLACE TRIGGER trg_cpl_complaint_pen
BEFORE INSERT OR UPDATE OF amount_original, currency_id ON tb_cpl_complaint
FOR EACH ROW
DECLARE
  v_rate tb_cfg_currency.exchange_rate_pen%TYPE;
BEGIN
  SELECT exchange_rate_pen
    INTO v_rate
    FROM tb_cfg_currency
   WHERE currency_id = :NEW.currency_id;

  :NEW.amount_pen := ROUND(NVL(:NEW.amount_original, 0) * v_rate, 2);
EXCEPTION
  WHEN NO_DATA_FOUND THEN
    RAISE_APPLICATION_ERROR(-20101,
      'La moneda ' || :NEW.currency_id || ' no existe en TB_CFG_CURRENCY.');
END;
/

-- =============================================================================
-- SECCION 6: Triggers de investigación
-- =============================================================================

-- Impide modificar o borrar el historial de estados.
CREATE OR REPLACE TRIGGER trg_inv_history_immutable
BEFORE UPDATE OR DELETE ON tb_inv_status_history
BEGIN
  RAISE_APPLICATION_ERROR(-20010,
    'TB_INV_STATUS_HISTORY es inmutable: no se permite UPDATE ni DELETE.');
END;
/

-- Rechaza una asignación activa si el efectivo ya alcanzó el límite de casos activos.
-- El límite es la constante c_max_cases. FOR UPDATE serializa asignaciones concurrentes al mismo efectivo.
CREATE OR REPLACE TRIGGER trg_check_max_active_cases
BEFORE INSERT ON tb_inv_assignment
FOR EACH ROW
WHEN (NEW.end_date IS NULL)
DECLARE
  c_max_cases CONSTANT NUMBER := 15;
  v_count     NUMBER;
BEGIN
  BEGIN
    SELECT NVL(active_case_count, 0) INTO v_count
      FROM tb_staff_officer
     WHERE officer_cip = :NEW.officer_cip
       FOR UPDATE;
  EXCEPTION WHEN NO_DATA_FOUND THEN
    RAISE_APPLICATION_ERROR(-20003, 'Oficial inexistente: ' || :NEW.officer_cip);
  END;

  IF v_count >= c_max_cases THEN
    RAISE_APPLICATION_ERROR(-20001,
      'El oficial ' || :NEW.officer_cip || ' alcanzo el limite de ' || c_max_cases ||
      ' casos activos. Asignacion rechazada.');
  END IF;
END;
/

-- Mantiene is_active según end_date: 'Y' mientras la asignación no tenga fecha de fin.
CREATE OR REPLACE TRIGGER trg_inv_assign_active_flag
BEFORE INSERT OR UPDATE OF end_date ON tb_inv_assignment
FOR EACH ROW
BEGIN
  :NEW.is_active := CASE WHEN :NEW.end_date IS NULL THEN 'Y' ELSE 'N' END;
END;
/

-- Mantiene tb_staff_officer.active_case_count al insertar, actualizar o borrar asignaciones.
CREATE OR REPLACE TRIGGER trg_inv_assign_count
AFTER INSERT OR UPDATE OR DELETE ON tb_inv_assignment
FOR EACH ROW
BEGIN
  IF INSERTING THEN
    IF :NEW.end_date IS NULL THEN
      UPDATE tb_staff_officer SET active_case_count = NVL(active_case_count,0) + 1
       WHERE officer_cip = :NEW.officer_cip;
    END IF;
  ELSIF DELETING THEN
    IF :OLD.end_date IS NULL THEN
      UPDATE tb_staff_officer SET active_case_count = GREATEST(NVL(active_case_count,0) - 1, 0)
       WHERE officer_cip = :OLD.officer_cip;
    END IF;
  ELSE
    IF :OLD.end_date IS NULL THEN
      UPDATE tb_staff_officer SET active_case_count = GREATEST(NVL(active_case_count,0) - 1, 0)
       WHERE officer_cip = :OLD.officer_cip;
    END IF;
    IF :NEW.end_date IS NULL THEN
      UPDATE tb_staff_officer SET active_case_count = NVL(active_case_count,0) + 1
       WHERE officer_cip = :NEW.officer_cip;
    END IF;
  END IF;
END;
/
