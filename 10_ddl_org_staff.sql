-- =============================================================================
-- 10_ddl_org_staff.sql | Ejecutar como GEO_OWNER
-- =============================================================================
-- PROPÓSITO
--   Crea la estructura (DDL) de las 6 tablas base del sistema: moneda, jerarquía
--   territorial policial (división > comisaría > sector) y personal policial
--   (grado y efectivo). Son las tablas de las que dependen las denuncias y las
--   investigaciones de Andy y John.
--
-- RELACIONES
--   TB_ORG_DIVISION 1---N TB_ORG_STATION 1---N TB_TERR_SECTOR
--   TB_ORG_STATION  1---N TB_STAFF_OFFICER N---1 TB_STAFF_RANK
--   TB_STAFF_OFFICER N---1 TB_STAFF_OFFICER   (relación recursiva: superior directo)
--   TB_CFG_CURRENCY queda independiente, la usarán las denuncias para el monto.
--
-- ALMACENAMIENTO
--   Todas las tablas y los índices se crean explícitamente en el tablespace TS_GEO_DATA
--   (definido en 01_security_setup.sql). Los índices de las llaves primarias y de los
--   valores únicos, y el índice espacial, usan el tablespace por defecto de GEO_OWNER,
--   que también es TS_GEO_DATA.
--
-- NOMENCLATURA (exigida por el sílabo)
--   TB_ tablas | PK_ llave primaria | FK_ llave foránea | UK_ valor único
--   CK_ restricción CHECK | IDX_ índices | SEQ_ secuencias | FN_ funciones
-- =============================================================================

-- ---- Secuencias --------------------------------------------------------------
-- Generan los IDs automáticos de las tablas que no usan un código externo.
-- Empiezan por encima de los IDs usados en 20_load_org_staff.sql para que los
-- registros nuevos que cree la aplicación nunca choquen con los de la carga inicial.
-- (TB_STAFF_OFFICER no tiene secuencia: su llave es el CIP, que asigna la Policía.)
CREATE SEQUENCE seq_cfg_currency START WITH 10;
CREATE SEQUENCE seq_org_division START WITH 100;
CREATE SEQUENCE seq_org_station  START WITH 100;
CREATE SEQUENCE seq_terr_sector  START WITH 1000;
CREATE SEQUENCE seq_staff_rank   START WITH 10;

-- ---- 1. TB_CFG_CURRENCY ------------------------------------------------------
-- Catálogo de monedas con su tasa de conversión a soles (PEN). Permite que el
-- cliente registre montos de extorsión en soles, dólares o euros y el sistema
-- los convierta a una moneda común para reportes.
CREATE TABLE tb_cfg_currency (
  currency_id       NUMBER(3)    NOT NULL,   -- identificador (1 = PEN, 2 = USD, 3 = EUR)
  currency_code     VARCHAR2(3)  NOT NULL,   -- código ISO 4217 de la moneda
  currency_name     VARCHAR2(50) NOT NULL,   -- nombre de la moneda
  exchange_rate_pen NUMBER(10,4) NOT NULL,   -- soles (PEN) por 1 unidad de esta moneda
  CONSTRAINT pk_cfg_currency      PRIMARY KEY (currency_id),
  CONSTRAINT uk_cfg_currency_code UNIQUE (currency_code),      -- no repetir código de moneda
  CONSTRAINT ck_cfg_currency_rate CHECK (exchange_rate_pen > 0) -- una tasa nunca es cero ni negativa
) TABLESPACE ts_geo_data;

-- ---- 2. TB_ORG_DIVISION ------------------------------------------------------
-- División Policial (DIVPOL): nivel superior de la organización territorial.
-- Agrupa varias comisarías.
CREATE TABLE tb_org_division (
  division_id   NUMBER(5)     NOT NULL,   -- identificador de la división
  division_name VARCHAR2(100) NOT NULL,   -- nombre oficial de la división
  region_name   VARCHAR2(60)  NOT NULL,   -- región policial a la que pertenece
  CONSTRAINT pk_org_division PRIMARY KEY (division_id)
) TABLESPACE ts_geo_data;

-- ---- 3. TB_ORG_STATION -------------------------------------------------------
-- Comisaría sectorial. Responde a una división y tiene a su cargo uno o varios
-- sectores vecinales. Es también la dependencia de adscripción de los efectivos.
CREATE TABLE tb_org_station (
  station_id   NUMBER(5)     NOT NULL,   -- identificador de la comisaría
  division_id  NUMBER(5)     NOT NULL,   -- división de la que depende
  station_name VARCHAR2(100) NOT NULL,   -- nombre de la comisaría
  address      VARCHAR2(200) NOT NULL,   -- dirección física
  CONSTRAINT pk_org_station PRIMARY KEY (station_id),
  CONSTRAINT fk_org_station_division FOREIGN KEY (division_id) REFERENCES tb_org_division (division_id)
) TABLESPACE ts_geo_data;

-- ---- 4. TB_TERR_SECTOR -------------------------------------------------------
-- Sector vecinal o cuadrante de patrullaje. Cada denuncia se asigna a un sector
-- según su ubicación GPS. Se guarda de dos formas:
--   * Bounding box (min/max de latitud y longitud): filtro rápido y simple.
--   * polygon_area (SDO_GEOMETRY): polígono de Oracle Spatial para la
--     verificación exacta de si un punto cae dentro del sector.
CREATE TABLE tb_terr_sector (
  sector_id    NUMBER(8)     NOT NULL,   -- identificador del sector
  station_id   NUMBER(5)     NOT NULL,   -- comisaría con jurisdicción sobre el sector
  sector_name  VARCHAR2(100) NOT NULL,   -- nombre del sector
  min_lat      NUMBER(10,7)  NOT NULL,   -- latitud mínima (borde sur)
  max_lat      NUMBER(10,7)  NOT NULL,   -- latitud máxima (borde norte)
  min_lon      NUMBER(10,7)  NOT NULL,   -- longitud mínima (borde oeste)
  max_lon      NUMBER(10,7)  NOT NULL,   -- longitud máxima (borde este)
  polygon_area SDO_GEOMETRY,             -- polígono SRID 4326 (GPS), construido desde el bounding box
  CONSTRAINT pk_terr_sector PRIMARY KEY (sector_id),
  CONSTRAINT fk_terr_sector_station FOREIGN KEY (station_id) REFERENCES tb_org_station (station_id),
  CONSTRAINT ck_terr_sector_lat CHECK (min_lat < max_lat),   -- el borde sur debe estar al sur del norte
  CONSTRAINT ck_terr_sector_lon CHECK (min_lon < max_lon)    -- el borde oeste debe estar al oeste del este
) TABLESPACE ts_geo_data;

-- ---- 5. TB_STAFF_RANK --------------------------------------------------------
-- Catálogo de grados policiales (Comandante, Mayor, Capitán, Teniente,
-- Suboficial). hierarchy_level permite comparar grados: un número menor es un
-- grado superior. Se usa para validar que un superior tenga mayor grado.
CREATE TABLE tb_staff_rank (
  rank_id         NUMBER(3)    NOT NULL,   -- identificador del grado
  rank_name       VARCHAR2(50) NOT NULL,   -- nombre del grado
  hierarchy_level NUMBER(2)    NOT NULL,   -- 1 = mando superior, mayor número = grado inferior
  CONSTRAINT pk_staff_rank      PRIMARY KEY (rank_id),
  CONSTRAINT uk_staff_rank_name UNIQUE (rank_name)
) TABLESPACE ts_geo_data;

-- ---- 6. TB_STAFF_OFFICER -----------------------------------------------------
-- Efectivo policial. Tiene grado, comisaría de adscripción y, opcionalmente, un
-- superior jerárquico directo (otra fila de esta misma tabla: relación recursiva).
-- Sobre esta tabla se asignan después los casos de investigación.
CREATE TABLE tb_staff_officer (
  officer_cip       VARCHAR2(15) NOT NULL,   -- CIP: código de identificación policial (llave)
  first_name        VARCHAR2(60) NOT NULL,   -- nombres
  last_name         VARCHAR2(60) NOT NULL,   -- apellidos
  rank_id           NUMBER(3)    NOT NULL,   -- grado que ostenta
  station_id        NUMBER(5)    NOT NULL,   -- comisaría donde está adscrito
  supervisor_cip    VARCHAR2(15),            -- CIP del superior directo, NULL en el mando más alto
  specialty         VARCHAR2(60) NOT NULL,   -- especialidad del efectivo
  active_case_count NUMBER(4)    DEFAULT 0 NOT NULL,  -- casos activos como investigador principal, lo mantiene el trigger del límite de casos (John)
  CONSTRAINT pk_staff_officer PRIMARY KEY (officer_cip),
  CONSTRAINT fk_staff_officer_rank    FOREIGN KEY (rank_id)        REFERENCES tb_staff_rank (rank_id),
  CONSTRAINT fk_staff_officer_station FOREIGN KEY (station_id)     REFERENCES tb_org_station (station_id),
  CONSTRAINT fk_staff_officer_super   FOREIGN KEY (supervisor_cip) REFERENCES tb_staff_officer (officer_cip),
  -- Un efectivo no puede ser su propio superior.
  CONSTRAINT ck_staff_officer_super   CHECK (supervisor_cip IS NULL OR supervisor_cip <> officer_cip),
  -- Solo se admiten las especialidades del dominio del negocio.
  CONSTRAINT ck_staff_officer_spec    CHECK (specialty IN ('CRIMINAL_INVESTIGATION', 'PUBLIC_ORDER', 'INTELLIGENCE')),
  -- El contador de casos nunca puede ser negativo.
  CONSTRAINT ck_staff_officer_cases   CHECK (active_case_count >= 0)
) TABLESPACE ts_geo_data;

-- ---- Índices sobre llaves foráneas -------------------------------------------
-- Oracle no crea índices automáticamente para las FK. Se agregan para acelerar
-- los JOIN y evitar bloqueos al borrar o actualizar filas padre.
CREATE INDEX idx_org_station_division  ON tb_org_station (division_id) TABLESPACE ts_geo_data;
CREATE INDEX idx_terr_sector_station   ON tb_terr_sector (station_id) TABLESPACE ts_geo_data;
CREATE INDEX idx_staff_officer_rank    ON tb_staff_officer (rank_id) TABLESPACE ts_geo_data;
CREATE INDEX idx_staff_officer_station ON tb_staff_officer (station_id) TABLESPACE ts_geo_data;
CREATE INDEX idx_staff_officer_super   ON tb_staff_officer (supervisor_cip) TABLESPACE ts_geo_data;

-- ---- Función FN_BUILD_RECT_POLYGON -------------------------------------------
-- Recibe los 4 bordes de un sector y devuelve un polígono rectangular de Oracle
-- Spatial. Las coordenadas van en orden (longitud, latitud) porque en SDO_GEOMETRY
-- x = longitud e y = latitud. SRID 4326 es el sistema GPS (WGS84). El polígono se
-- cierra repitiendo el primer punto al final.
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

-- ---- Metadata e índice espaciales --------------------------------------------
-- Oracle Spatial exige registrar la columna geométrica (nombre, rango de
-- coordenadas, tolerancia y SRID) ANTES de crear su índice espacial.
--   Longitud: -180 a 180 | Latitud: -90 a 90 | tolerancia 0.005 (metros, en datos geodésicos).
INSERT INTO user_sdo_geom_metadata (table_name, column_name, diminfo, srid)
VALUES ('TB_TERR_SECTOR', 'POLYGON_AREA',
        SDO_DIM_ARRAY(SDO_DIM_ELEMENT('LONGITUDE', -180, 180, 0.005),
                      SDO_DIM_ELEMENT('LATITUDE',   -90,  90, 0.005)),
        4326);
COMMIT;

-- Índice espacial: acelera las búsquedas "¿qué sector contiene este punto GPS?"
-- que usa PKG_ORG_MGMT.find_sector_by_location (operador SDO_ANYINTERACT).
CREATE INDEX idx_terr_sector_polygon ON tb_terr_sector (polygon_area)
  INDEXTYPE IS MDSYS.SPATIAL_INDEX_V2;
