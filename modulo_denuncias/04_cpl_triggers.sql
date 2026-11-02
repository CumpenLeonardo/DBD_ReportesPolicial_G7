-- =====================================================================
-- GEO-DENUNCIA | Grupo 07 | Modulo CPL (Denuncias)
-- 04_cpl_triggers.sql : triggers del modulo de Denuncias
--   1. trg_cpl_estab_geom     : genera location_geom desde lat/lon
--   2. trg_cpl_complaint_geom : genera incident_location desde lat/lon
--   3. trg_cpl_complaint_pen  : calcula amount_pen = amount_original * tasa
--
-- Prerrequisito: 03_cpl_ddl.sql ejecutado.
-- Ejecutar con F5 (Run Script) conectado como el dueno del esquema.
-- =====================================================================


-- ---------------------------------------------------------------------
-- 1. Geometria del establecimiento
--    SRID 4326: SDO_POINT_TYPE(X = longitud, Y = latitud, Z = NULL)
-- ---------------------------------------------------------------------

CREATE OR REPLACE TRIGGER trg_cpl_estab_geom
BEFORE INSERT OR UPDATE OF latitude, longitude ON tb_cpl_establishment
FOR EACH ROW
BEGIN
  :NEW.location_geom := SDO_GEOMETRY(
        2001,                                            -- punto 2D
        4326,                                            -- WGS 84
        SDO_POINT_TYPE(:NEW.longitude, :NEW.latitude, NULL),
        NULL, NULL);
END;
/


-- ---------------------------------------------------------------------
-- 2. Geometria del lugar del incidente
-- ---------------------------------------------------------------------
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


-- ---------------------------------------------------------------------
-- 3. Conversion del monto exigido a Soles
--    Se recalcula solo si cambia el monto o la moneda de la denuncia.
--    Si luego cambia la tasa en TB_CFG_CURRENCY, las denuncias antiguas
--    conservan el monto en soles vigente al momento del registro.
-- ---------------------------------------------------------------------
CREATE OR REPLACE TRIGGER trg_cpl_complaint_pen
BEFORE INSERT OR UPDATE OF amount_original, currency_id ON tb_cpl_complaint
FOR EACH ROW
DECLARE
  v_rate  tb_cfg_currency.exchange_rate_pen%TYPE;
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


-- ---------------------------------------------------------------------
-- 4. VERIFICACION: estado de los triggers
-- ---------------------------------------------------------------------
SELECT trigger_name, table_name, triggering_event, status
  FROM user_triggers
 WHERE trigger_name LIKE 'TRG_CPL%'
 ORDER BY table_name, trigger_name;

SELECT name, type, line, text
  FROM user_errors
 WHERE name LIKE 'TRG_CPL%';


-- ---------------------------------------------------------------------
-- 5. PRUEBA (se deshace al final con ROLLBACK)
-- ---------------------------------------------------------------------
INSERT INTO tb_cpl_modality VALUES (seq_cpl_modality.NEXTVAL, 'Cobro de cupo', 'CRITICAL');

INSERT INTO tb_cpl_establishment (establishment_id, establishment_name, establishment_type,
       address, latitude, longitude)
VALUES (seq_cpl_establishment.NEXTVAL, 'Bodega Don Pepe', 'COMMERCE',
        'Av. Canto Grande 200', -11.9605000, -76.9895000);

INSERT INTO tb_cpl_reporter VALUES (seq_cpl_reporter.NEXTVAL, '70123456', 'Rosa',
       'Quispe Huaman', 'M', 'Av. Canto Grande 123', '987654321', NULL);

-- Denuncia en USD: amount_pen debe ser 500 * 3.75 = 1875.00
INSERT INTO tb_cpl_complaint (complaint_id, sector_id, modality_id, establishment_id,
       incident_date, is_anonymous, currency_id, amount_original, payment_frequency,
       latitude, longitude, incident_address, id_reporter)
VALUES (seq_cpl_complaint.NEXTVAL, 101, seq_cpl_modality.CURRVAL,
        seq_cpl_establishment.CURRVAL, SYSTIMESTAMP - INTERVAL '2' DAY, 'N',
        2, 500, 'WEEKLY', -11.9600000, -76.9900000, 'Jr. Las Flores 456',
        seq_cpl_reporter.CURRVAL);

-- Resultado de los triggers 2 y 3
SELECT complaint_id, currency_id, amount_original, amount_pen,
       c.incident_location.sdo_point.x AS lon_x,
       c.incident_location.sdo_point.y AS lat_y
  FROM tb_cpl_complaint c;

-- Uso del indice espacial: denuncias a menos de 1 km de cada establecimiento
SELECT e.establishment_name, c.complaint_id, c.incident_address
  FROM tb_cpl_establishment e, tb_cpl_complaint c
 WHERE SDO_WITHIN_DISTANCE(c.incident_location, e.location_geom,
                           'distance=1000 unit=M') = 'TRUE';

-- Debe fallar con ORA-20101 (moneda inexistente)
INSERT INTO tb_cpl_complaint (complaint_id, sector_id, modality_id, incident_date,
       is_anonymous, currency_id, amount_original, latitude, longitude,
       incident_address, id_reporter)
VALUES (seq_cpl_complaint.NEXTVAL, 101, seq_cpl_modality.CURRVAL, SYSTIMESTAMP,
        'N', 9, 100, -11.9600000, -76.9900000, 'Jr. Prueba 1', seq_cpl_reporter.CURRVAL);

ROLLBACK;
