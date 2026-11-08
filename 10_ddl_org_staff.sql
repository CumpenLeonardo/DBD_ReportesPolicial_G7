-- =============================================================================
-- 10_ddl_org_staff.sql | Ejecutar como GEO_OWNER
-- Tablas base: moneda, territorio policial (división > comisaría > sector) y
-- personal (grado y efectivo). Las denuncias e investigaciones dependen de ellas.
-- Todo se crea en el tablespace TS_GEO_DATA (los índices automáticos de PK y UK
-- usan el tablespace por defecto de GEO_OWNER, que es el mismo).
-- Nomenclatura: TB_ tablas | PK_ FK_ UK_ CK_ restricciones | IDX_ índices | SEQ_ secuencias
-- =============================================================================

-- Secuencias para los IDs automáticos. Empiezan por encima de los IDs de la carga
-- inicial para no chocar con ellos. El efectivo no usa secuencia: su llave es el CIP.
CREATE SEQUENCE seq_cfg_currency START WITH 10;
CREATE SEQUENCE seq_org_division START WITH 100;
CREATE SEQUENCE seq_org_station  START WITH 100;
CREATE SEQUENCE seq_terr_sector  START WITH 1000;
CREATE SEQUENCE seq_staff_rank   START WITH 10;

-- Monedas y su tasa de conversión a soles (PEN).
CREATE TABLE tb_cfg_currency (
  currency_id       NUMBER(3)    NOT NULL,
  currency_code     VARCHAR2(3)  NOT NULL,   -- código ISO: PEN, USD, EUR
  currency_name     VARCHAR2(50) NOT NULL,
  exchange_rate_pen NUMBER(10,4) NOT NULL,   -- soles por 1 unidad de la moneda
  CONSTRAINT pk_cfg_currency      PRIMARY KEY (currency_id),
  CONSTRAINT uk_cfg_currency_code UNIQUE (currency_code),
  CONSTRAINT ck_cfg_currency_rate CHECK (exchange_rate_pen > 0)
) TABLESPACE ts_geo_data;

-- División policial (DIVPOL): agrupa comisarías.
CREATE TABLE tb_org_division (
  division_id   NUMBER(5)     NOT NULL,
  division_name VARCHAR2(100) NOT NULL,
  region_name   VARCHAR2(60)  NOT NULL,
  CONSTRAINT pk_org_division PRIMARY KEY (division_id)
) TABLESPACE ts_geo_data;

-- Comisaría: depende de una división y es la sede de adscripción de los efectivos.
CREATE TABLE tb_org_station (
  station_id   NUMBER(5)     NOT NULL,
  division_id  NUMBER(5)     NOT NULL,
  station_name VARCHAR2(100) NOT NULL,
  address      VARCHAR2(200) NOT NULL,
  CONSTRAINT pk_org_station PRIMARY KEY (station_id),
  CONSTRAINT fk_org_station_division FOREIGN KEY (division_id) REFERENCES tb_org_division (division_id)
) TABLESPACE ts_geo_data;

-- Sector vecinal. Cada denuncia se asigna a un sector según su punto GPS.
-- Se guarda como caja (min/max de latitud y longitud, filtro rápido) y como
-- polígono de Oracle Spatial (verificación exacta).
CREATE TABLE tb_terr_sector (
  sector_id    NUMBER(8)     NOT NULL,
  station_id   NUMBER(5)     NOT NULL,
  sector_name  VARCHAR2(100) NOT NULL,
  min_lat      NUMBER(10,7)  NOT NULL,
  max_lat      NUMBER(10,7)  NOT NULL,
  min_lon      NUMBER(10,7)  NOT NULL,
  max_lon      NUMBER(10,7)  NOT NULL,
  polygon_area SDO_GEOMETRY,                 -- SRID 4326 (GPS), se construye desde la caja
  CONSTRAINT pk_terr_sector PRIMARY KEY (sector_id),
  CONSTRAINT fk_terr_sector_station FOREIGN KEY (station_id) REFERENCES tb_org_station (station_id),
  CONSTRAINT ck_terr_sector_lat CHECK (min_lat < max_lat),
  CONSTRAINT ck_terr_sector_lon CHECK (min_lon < max_lon)
) TABLESPACE ts_geo_data;

-- Grados policiales. Un hierarchy_level menor es un grado superior (1 = mando superior).
CREATE TABLE tb_staff_rank (
  rank_id         NUMBER(3)    NOT NULL,
  rank_name       VARCHAR2(50) NOT NULL,
  hierarchy_level NUMBER(2)    NOT NULL,
  CONSTRAINT pk_staff_rank      PRIMARY KEY (rank_id),
  CONSTRAINT uk_staff_rank_name UNIQUE (rank_name)
) TABLESPACE ts_geo_data;

-- Efectivo policial. supervisor_cip apunta a otro efectivo de la misma tabla
-- (superior directo, NULL en el mando más alto).
CREATE TABLE tb_staff_officer (
  officer_cip       VARCHAR2(15) NOT NULL,   -- CIP: código de identificación policial
  first_name        VARCHAR2(60) NOT NULL,
  last_name         VARCHAR2(60) NOT NULL,
  rank_id           NUMBER(3)    NOT NULL,
  station_id        NUMBER(5)    NOT NULL,
  supervisor_cip    VARCHAR2(15),
  specialty         VARCHAR2(60) NOT NULL,
  active_case_count NUMBER(4)    DEFAULT 0 NOT NULL,  -- casos activos como investigador principal, lo mantiene el trigger de John
  CONSTRAINT pk_staff_officer PRIMARY KEY (officer_cip),
  CONSTRAINT fk_staff_officer_rank    FOREIGN KEY (rank_id)        REFERENCES tb_staff_rank (rank_id),
  CONSTRAINT fk_staff_officer_station FOREIGN KEY (station_id)     REFERENCES tb_org_station (station_id),
  CONSTRAINT fk_staff_officer_super   FOREIGN KEY (supervisor_cip) REFERENCES tb_staff_officer (officer_cip),
  CONSTRAINT ck_staff_officer_super   CHECK (supervisor_cip IS NULL OR supervisor_cip <> officer_cip),
  CONSTRAINT ck_staff_officer_spec    CHECK (specialty IN ('CRIMINAL_INVESTIGATION', 'PUBLIC_ORDER', 'INTELLIGENCE')),
  CONSTRAINT ck_staff_officer_cases   CHECK (active_case_count >= 0)
) TABLESPACE ts_geo_data;

-- Índices sobre las llaves foráneas (Oracle no los crea solo).
CREATE INDEX idx_org_station_division  ON tb_org_station (division_id) TABLESPACE ts_geo_data;
CREATE INDEX idx_terr_sector_station   ON tb_terr_sector (station_id) TABLESPACE ts_geo_data;
CREATE INDEX idx_staff_officer_rank    ON tb_staff_officer (rank_id) TABLESPACE ts_geo_data;
CREATE INDEX idx_staff_officer_station ON tb_staff_officer (station_id) TABLESPACE ts_geo_data;
CREATE INDEX idx_staff_officer_super   ON tb_staff_officer (supervisor_cip) TABLESPACE ts_geo_data;

-- Construye el polígono rectangular de un sector a partir de su caja.
-- En SDO_GEOMETRY x = longitud e y = latitud, y el polígono se cierra repitiendo el primer punto.
CREATE OR REPLACE FUNCTION fn_build_rect_polygon (
  p_min_lat IN NUMBER, p_max_lat IN NUMBER, p_min_lon IN NUMBER, p_max_lon IN NUMBER
) RETURN SDO_GEOMETRY IS
BEGIN
  RETURN SDO_GEOMETRY(2003, 4326, NULL, SDO_ELEM_INFO_ARRAY(1, 1003, 1),
           SDO_ORDINATE_ARRAY(p_min_lon, p_min_lat, p_max_lon, p_min_lat,
                              p_max_lon, p_max_lat, p_min_lon, p_max_lat,
                              p_min_lon, p_min_lat));
END fn_build_rect_polygon;
/

-- Oracle Spatial exige registrar la columna geométrica antes de crear su índice.
INSERT INTO user_sdo_geom_metadata (table_name, column_name, diminfo, srid)
VALUES ('TB_TERR_SECTOR', 'POLYGON_AREA',
        SDO_DIM_ARRAY(SDO_DIM_ELEMENT('LONGITUDE', -180, 180, 0.005),
                      SDO_DIM_ELEMENT('LATITUDE',   -90,  90, 0.005)),
        4326);
COMMIT;

-- Índice espacial: acelera la búsqueda del sector que contiene un punto GPS.
CREATE INDEX idx_terr_sector_polygon ON tb_terr_sector (polygon_area)
  INDEXTYPE IS MDSYS.SPATIAL_INDEX_V2
  PARAMETERS ('tablespace=ts_geo_data');
