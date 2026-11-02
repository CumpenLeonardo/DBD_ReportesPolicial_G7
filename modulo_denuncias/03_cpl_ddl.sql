-- =====================================================================
-- GEO-DENUNCIA | Grupo 07 | Modulo CPL (Denuncias)
-- 03_cpl_ddl.sql : secuencias, tablas, restricciones, indices de FK,
--                  metadata espacial e indices espaciales.
--
-- PRERREQUISITOS (deben existir antes de ejecutar):
--   Leonardo: TB_CFG_CURRENCY, TB_TERR_SECTOR, TB_STAFF_OFFICER
--   John    : TB_COM_NEIGHBORHOOD_ASSOC
--
-- ORDEN DE CREACION (por dependencias de FK):
--   MODALITY -> ESTABLISHMENT -> REPORTER -> COMPLAINT_PROTECTION
--   -> COMPLAINT -> DIGITAL_EVIDENCE
--
-- Ejecutar con F5 (Run Script) en SQL Developer.
-- =====================================================================


-- ---------------------------------------------------------------------
-- 0. LIMPIEZA (permite re-ejecutar el script)
--    Orden inverso al de creacion.
-- ---------------------------------------------------------------------

BEGIN
  FOR t IN (SELECT table_name FROM user_tables
            WHERE table_name IN ('TB_CPL_DIGITAL_EVIDENCE','TB_CPL_COMPLAINT',
                                 'TB_CPL_COMPLAINT_PROTECTION','TB_CPL_REPORTER',
                                 'TB_CPL_ESTABLISHMENT','TB_CPL_MODALITY')) LOOP
    EXECUTE IMMEDIATE 'DROP TABLE ' || t.table_name || ' CASCADE CONSTRAINTS PURGE';
  END LOOP;

  FOR s IN (SELECT sequence_name FROM user_sequences
            WHERE sequence_name LIKE 'SEQ_CPL_%') LOOP
    EXECUTE IMMEDIATE 'DROP SEQUENCE ' || s.sequence_name;
  END LOOP;

  DELETE FROM user_sdo_geom_metadata
   WHERE table_name IN ('TB_CPL_ESTABLISHMENT','TB_CPL_COMPLAINT');
  COMMIT;
END;
/


-- ---------------------------------------------------------------------
-- 1. SECUENCIAS (generan las PK)
-- ---------------------------------------------------------------------
CREATE SEQUENCE seq_cpl_modality      START WITH 1    INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE seq_cpl_establishment START WITH 1000 INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE seq_cpl_reporter      START WITH 1000 INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE seq_cpl_protection    START WITH 5000 INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE seq_cpl_complaint     START WITH 100001 INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE seq_cpl_evidence      START WITH 1    INCREMENT BY 1 NOCACHE;


-- ---------------------------------------------------------------------
-- 2. TB_CPL_MODALITY : catalogo de modalidades extorsivas
-- ---------------------------------------------------------------------
CREATE TABLE tb_cpl_modality (
  modality_id     NUMBER(3)
                  CONSTRAINT pk_cpl_modality PRIMARY KEY,
  modality_name   VARCHAR2(80)
                  CONSTRAINT nn_cpl_modality_name NOT NULL,
  severity_level  VARCHAR2(20)
                  CONSTRAINT nn_cpl_modality_sev NOT NULL,
  CONSTRAINT uk_cpl_modality_name UNIQUE (modality_name),
  CONSTRAINT chk_cpl_modality_sev CHECK (severity_level IN ('HIGH','CRITICAL'))
);


-- ---------------------------------------------------------------------
-- 3. TB_CPL_ESTABLISHMENT : comercios o paraderos afectados
-- ---------------------------------------------------------------------
CREATE TABLE tb_cpl_establishment (
  establishment_id    NUMBER(10)
                      CONSTRAINT pk_cpl_establishment PRIMARY KEY,
  establishment_name  VARCHAR2(120)
                      CONSTRAINT nn_cpl_estab_name NOT NULL,
  establishment_type  VARCHAR2(40)
                      CONSTRAINT nn_cpl_estab_type NOT NULL,
  address             VARCHAR2(200)
                      CONSTRAINT nn_cpl_estab_address NOT NULL,
  latitude            NUMBER(10,7)
                      CONSTRAINT nn_cpl_estab_lat NOT NULL,
  longitude           NUMBER(10,7)
                      CONSTRAINT nn_cpl_estab_lon NOT NULL,
  location_geom       SDO_GEOMETRY,
  CONSTRAINT chk_cpl_estab_type CHECK (establishment_type IN
             ('COMMERCE','TRANSPORT_STOP','WORKSHOP','RESIDENCE')),
  CONSTRAINT chk_cpl_estab_lat  CHECK (latitude  BETWEEN -90  AND 90),
  CONSTRAINT chk_cpl_estab_lon  CHECK (longitude BETWEEN -180 AND 180)
);


-- ---------------------------------------------------------------------
-- 4. TB_CPL_REPORTER : datos reales del denunciante
-- ---------------------------------------------------------------------
CREATE TABLE tb_cpl_reporter (
  id_reporter           NUMBER(10)
                        CONSTRAINT pk_cpl_reporter PRIMARY KEY,
  personal_document_id  VARCHAR2(20)
                        CONSTRAINT nn_cpl_rep_doc NOT NULL,
  first_name            VARCHAR2(50)
                        CONSTRAINT nn_cpl_rep_fname NOT NULL,
  last_name             VARCHAR2(50)
                        CONSTRAINT nn_cpl_rep_lname NOT NULL,
  gender                CHAR(1)
                        CONSTRAINT nn_cpl_rep_gender NOT NULL,
  address               VARCHAR2(200)
                        CONSTRAINT nn_cpl_rep_address NOT NULL,
  phone_number          VARCHAR2(15)
                        CONSTRAINT nn_cpl_rep_phone NOT NULL,
  email                 VARCHAR2(100),
  CONSTRAINT uk_cpl_rep_doc    UNIQUE (personal_document_id),
  CONSTRAINT chk_cpl_rep_gender CHECK (gender IN ('H','M'))
);


-- ---------------------------------------------------------------------
-- 5. TB_CPL_COMPLAINT_PROTECTION : codigo protegido del denunciante anonimo
--    La identidad real queda aqui; la denuncia solo ve protected_code.
-- ---------------------------------------------------------------------
CREATE TABLE tb_cpl_complaint_protection (
  protected_code       NUMBER(10)
                       CONSTRAINT pk_cpl_protection PRIMARY KEY,
  id_reporter          NUMBER(10)
                       CONSTRAINT nn_cpl_prot_reporter NOT NULL,
  date_approved        TIMESTAMP DEFAULT SYSTIMESTAMP
                       CONSTRAINT nn_cpl_prot_date NOT NULL,
  approved_by_officer  VARCHAR2(15)
                       CONSTRAINT nn_cpl_prot_officer NOT NULL,
  CONSTRAINT fk_cpl_prot_reporter FOREIGN KEY (id_reporter)
             REFERENCES tb_cpl_reporter (id_reporter),
  CONSTRAINT fk_cpl_prot_officer  FOREIGN KEY (approved_by_officer)
             REFERENCES tb_staff_officer (officer_cip)
);


-- ---------------------------------------------------------------------
-- 6. TB_CPL_COMPLAINT : nucleo central (denuncias y alertas)
-- ---------------------------------------------------------------------
CREATE TABLE tb_cpl_complaint (
  complaint_id        NUMBER(12)
                      CONSTRAINT pk_cpl_complaint PRIMARY KEY,
  sector_id           NUMBER(8)
                      CONSTRAINT nn_cpl_cmp_sector NOT NULL,
  modality_id         NUMBER(3)
                      CONSTRAINT nn_cpl_cmp_modality NOT NULL,
  establishment_id    NUMBER(10),
  assoc_id            NUMBER(6),
  incident_date       TIMESTAMP
                      CONSTRAINT nn_cpl_cmp_incdate NOT NULL,
  registration_date   TIMESTAMP DEFAULT SYSTIMESTAMP
                      CONSTRAINT nn_cpl_cmp_regdate NOT NULL,
  is_anonymous        CHAR(1)
                      CONSTRAINT nn_cpl_cmp_anon NOT NULL,
  currency_id         NUMBER(3) DEFAULT 1
                      CONSTRAINT nn_cpl_cmp_currency NOT NULL,
  amount_original     NUMBER(12,2) DEFAULT 0
                      CONSTRAINT nn_cpl_cmp_amount NOT NULL,
  amount_pen          NUMBER(12,2) DEFAULT 0
                      CONSTRAINT nn_cpl_cmp_amount_pen NOT NULL,
  payment_frequency   VARCHAR2(30),
  extortionist_alias  VARCHAR2(200),
  current_status      VARCHAR2(30) DEFAULT 'REGISTRADO'
                      CONSTRAINT nn_cpl_cmp_status NOT NULL,
  latitude            NUMBER(10,7)
                      CONSTRAINT nn_cpl_cmp_lat NOT NULL,
  longitude           NUMBER(10,7)
                      CONSTRAINT nn_cpl_cmp_lon NOT NULL,
  incident_address    VARCHAR2(200)
                      CONSTRAINT nn_cpl_cmp_address NOT NULL,
  incident_location   SDO_GEOMETRY,
  id_reporter         NUMBER(10),
  protected_code      NUMBER(10),

  -- Llaves foraneas
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

  -- Dominios
  CONSTRAINT chk_cpl_cmp_anon      CHECK (is_anonymous IN ('Y','N')),
  CONSTRAINT chk_cpl_cmp_amount    CHECK (amount_original >= 0),
  CONSTRAINT chk_cpl_cmp_frequency CHECK (payment_frequency IN
             ('DAILY','WEEKLY','MONTHLY','ONE_TIME')),
  CONSTRAINT chk_cpl_cmp_status    CHECK (current_status IN
             ('REGISTRADO','VALIDADO_COMISARIA','INTERVENCION_PROGRAMADA',
              'DERIVADO_FISCALIA','ARCHIVADO')),
  CONSTRAINT chk_cpl_cmp_lat       CHECK (latitude  BETWEEN -90  AND 90),
  CONSTRAINT chk_cpl_cmp_lon       CHECK (longitude BETWEEN -180 AND 180),
  CONSTRAINT chk_cpl_cmp_dates     CHECK (incident_date <= registration_date),

  -- Exclusividad: o firmada (reporter) o sellada (codigo protegido), nunca ambas
  CONSTRAINT chk_cpl_cmp_identity CHECK (
       (is_anonymous = 'N' AND id_reporter IS NOT NULL AND protected_code IS NULL)
    OR (is_anonymous = 'Y' AND id_reporter IS NULL     AND protected_code IS NOT NULL)
  )
);


-- ---------------------------------------------------------------------
-- 7. TB_CPL_DIGITAL_EVIDENCE : evidencias multimedia (sin hash ni bytes)
-- ---------------------------------------------------------------------
CREATE TABLE tb_cpl_digital_evidence (
  evidence_id      NUMBER(12)
                   CONSTRAINT pk_cpl_evidence PRIMARY KEY,
  complaint_id     NUMBER(12)
                   CONSTRAINT nn_cpl_ev_complaint NOT NULL,
  uploaded_by_cip  VARCHAR2(15)
                   CONSTRAINT nn_cpl_ev_officer NOT NULL,
  evidence_type    VARCHAR2(40)
                   CONSTRAINT nn_cpl_ev_type NOT NULL,
  file_path        VARCHAR2(250)
                   CONSTRAINT nn_cpl_ev_path NOT NULL,
  description      VARCHAR2(200)
                   CONSTRAINT nn_cpl_ev_desc NOT NULL,
  upload_date      TIMESTAMP DEFAULT SYSTIMESTAMP
                   CONSTRAINT nn_cpl_ev_date NOT NULL,
  CONSTRAINT fk_cpl_ev_complaint FOREIGN KEY (complaint_id)
             REFERENCES tb_cpl_complaint (complaint_id),
  CONSTRAINT fk_cpl_ev_officer   FOREIGN KEY (uploaded_by_cip)
             REFERENCES tb_staff_officer (officer_cip),
  CONSTRAINT chk_cpl_ev_type CHECK (evidence_type IN
             ('AUDIO_THREAT','CHAT_SCREENSHOT','SECURITY_VIDEO','PHOTO'))
);


-- ---------------------------------------------------------------------
-- 8. INDICES SOBRE COLUMNAS FK
--    Oracle NO crea indices automaticos para las FK (solo para PK y UK).
--    Agregar TABLESPACE <tablespace_de_indices> cuando el equipo lo defina.
-- ---------------------------------------------------------------------
CREATE INDEX idx_cpl_prot_reporter ON tb_cpl_complaint_protection (id_reporter);
CREATE INDEX idx_cpl_prot_officer  ON tb_cpl_complaint_protection (approved_by_officer);
CREATE INDEX idx_cpl_cmp_sector    ON tb_cpl_complaint (sector_id);
CREATE INDEX idx_cpl_cmp_modality  ON tb_cpl_complaint (modality_id);
CREATE INDEX idx_cpl_cmp_estab     ON tb_cpl_complaint (establishment_id);
CREATE INDEX idx_cpl_cmp_assoc     ON tb_cpl_complaint (assoc_id);
CREATE INDEX idx_cpl_cmp_currency  ON tb_cpl_complaint (currency_id);
CREATE INDEX idx_cpl_cmp_reporter  ON tb_cpl_complaint (id_reporter);
CREATE INDEX idx_cpl_cmp_protcode  ON tb_cpl_complaint (protected_code);
CREATE INDEX idx_cpl_ev_complaint  ON tb_cpl_digital_evidence (complaint_id);
CREATE INDEX idx_cpl_ev_officer    ON tb_cpl_digital_evidence (uploaded_by_cip);

-- Apoyo a los reportes mensuales
CREATE INDEX idx_cpl_cmp_incdate   ON tb_cpl_complaint (incident_date);


-- ---------------------------------------------------------------------
-- 9. METADATA ESPACIAL (obligatoria ANTES del indice espacial)
--    SRID 4326 = WGS 84: X = longitud, Y = latitud.
--    Nombres de tabla y columna en MAYUSCULAS.
-- ---------------------------------------------------------------------
INSERT INTO user_sdo_geom_metadata (table_name, column_name, diminfo, srid)
VALUES ('TB_CPL_ESTABLISHMENT', 'LOCATION_GEOM',
        SDO_DIM_ARRAY(SDO_DIM_ELEMENT('Longitude', -180, 180, 0.05),
                      SDO_DIM_ELEMENT('Latitude',   -90,  90, 0.05)),
        4326);

INSERT INTO user_sdo_geom_metadata (table_name, column_name, diminfo, srid)
VALUES ('TB_CPL_COMPLAINT', 'INCIDENT_LOCATION',
        SDO_DIM_ARRAY(SDO_DIM_ELEMENT('Longitude', -180, 180, 0.05),
                      SDO_DIM_ELEMENT('Latitude',   -90,  90, 0.05)),
        4326);

COMMIT;


-- ---------------------------------------------------------------------
-- 10. INDICES ESPACIALES (R-tree)
--     layer_gtype=POINT: ambas columnas solo guardan puntos.
-- ---------------------------------------------------------------------
CREATE INDEX sidx_cpl_estab_geom ON tb_cpl_establishment (location_geom)
  INDEXTYPE IS MDSYS.SPATIAL_INDEX_V2
  PARAMETERS ('layer_gtype=POINT');

CREATE INDEX sidx_cpl_cmp_geom ON tb_cpl_complaint (incident_location)
  INDEXTYPE IS MDSYS.SPATIAL_INDEX_V2
  PARAMETERS ('layer_gtype=POINT');


-- ---------------------------------------------------------------------
-- 11. VERIFICACION
-- ---------------------------------------------------------------------
SELECT table_name, constraint_name, constraint_type
  FROM user_constraints
 WHERE table_name LIKE 'TB_CPL%'
 ORDER BY table_name, constraint_type, constraint_name;

SELECT table_name, column_name, srid FROM user_sdo_geom_metadata;

SELECT index_name, table_name, ityp_name, status
  FROM user_indexes
 WHERE index_type = 'DOMAIN';
