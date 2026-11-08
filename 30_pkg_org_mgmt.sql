-- =============================================================================
-- 30_pkg_org_mgmt.sql | Ejecutar como GEO_OWNER
-- PKG_ORG_MGMT: mantenimiento (insert, update, delete) de moneda, división,
-- comisaría, sector, grado y efectivo, más la lógica de negocio de esas tablas.
-- La aplicación debe usar este paquete en vez de DML directo para que se apliquen las reglas.
--   * insert_*  crea el registro y devuelve el ID generado en p_id.
--   * Errores propios: -20001 registro no encontrado | -20002 dato inválido.
--   * No hace COMMIT: la transacción la controla quien lo llama.
-- =============================================================================
CREATE OR REPLACE PACKAGE pkg_org_mgmt AS

  -- Moneda. La moneda base PEN (id 1) siempre vale 1.
  PROCEDURE insert_currency (p_code IN VARCHAR2, p_name IN VARCHAR2, p_rate IN NUMBER, p_id OUT NUMBER);
  PROCEDURE update_currency (p_id IN NUMBER, p_name IN VARCHAR2, p_rate IN NUMBER);
  PROCEDURE delete_currency (p_id IN NUMBER);
  -- Convierte un monto a soles con la tasa de la moneda (2 decimales). Lo usarán las denuncias.
  FUNCTION  convert_to_pen  (p_amount IN NUMBER, p_currency_id IN NUMBER) RETURN NUMBER;

  -- División y comisaría.
  PROCEDURE insert_division (p_name IN VARCHAR2, p_region IN VARCHAR2, p_id OUT NUMBER);
  PROCEDURE update_division (p_id IN NUMBER, p_name IN VARCHAR2, p_region IN VARCHAR2);
  PROCEDURE delete_division (p_id IN NUMBER);
  PROCEDURE insert_station  (p_division_id IN NUMBER, p_name IN VARCHAR2, p_address IN VARCHAR2, p_id OUT NUMBER);
  PROCEDURE update_station  (p_id IN NUMBER, p_division_id IN NUMBER, p_name IN VARCHAR2, p_address IN VARCHAR2);
  PROCEDURE delete_station  (p_id IN NUMBER);

  -- Sector: solo se informa la caja, el polígono se construye automáticamente.
  PROCEDURE insert_sector (p_station_id IN NUMBER, p_name IN VARCHAR2,
                           p_min_lat IN NUMBER, p_max_lat IN NUMBER,
                           p_min_lon IN NUMBER, p_max_lon IN NUMBER, p_id OUT NUMBER);
  PROCEDURE update_sector (p_id IN NUMBER, p_station_id IN NUMBER, p_name IN VARCHAR2,
                           p_min_lat IN NUMBER, p_max_lat IN NUMBER,
                           p_min_lon IN NUMBER, p_max_lon IN NUMBER);
  PROCEDURE delete_sector (p_id IN NUMBER);
  -- Asignación automática de sector: devuelve el sector que contiene el punto GPS, o NULL si no hay.
  FUNCTION  find_sector_by_location (p_latitude IN NUMBER, p_longitude IN NUMBER) RETURN NUMBER;

  -- Grado.
  PROCEDURE insert_rank (p_name IN VARCHAR2, p_level IN NUMBER, p_id OUT NUMBER);
  PROCEDURE update_rank (p_id IN NUMBER, p_name IN VARCHAR2, p_level IN NUMBER);
  PROCEDURE delete_rank (p_id IN NUMBER);

  -- Efectivo. Regla: el superior debe tener un grado mayor, lo que además evita ciclos de mando.
  -- active_case_count no se recibe: lo maneja el trigger del límite de casos.
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

  -- Se llama tras un UPDATE o DELETE: si no tocó ninguna fila, el ID no existe.
  PROCEDURE check_found (p_entity IN VARCHAR2, p_key IN VARCHAR2) IS
  BEGIN
    IF SQL%ROWCOUNT = 0 THEN
      RAISE_APPLICATION_ERROR(-20001, p_entity || ' not found: ' || p_key);
    END IF;
  END check_found;

  -- Regla de jerarquía: el superior debe tener un hierarchy_level menor (grado más alto).
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
      RAISE_APPLICATION_ERROR(-20002, 'Supervisor ' || p_supervisor_cip || ' must have a higher rank');
    END IF;
  EXCEPTION
    WHEN NO_DATA_FOUND THEN
      RAISE_APPLICATION_ERROR(-20001, 'Supervisor or rank not found');
  END check_supervisor;

  -- ---------------- Moneda ----------------
  PROCEDURE insert_currency (p_code IN VARCHAR2, p_name IN VARCHAR2, p_rate IN NUMBER, p_id OUT NUMBER) IS
  BEGIN
    p_id := seq_cfg_currency.NEXTVAL;
    INSERT INTO tb_cfg_currency VALUES (p_id, UPPER(p_code), p_name, p_rate);
  END insert_currency;

  PROCEDURE update_currency (p_id IN NUMBER, p_name IN VARCHAR2, p_rate IN NUMBER) IS
  BEGIN
    IF p_id = 1 AND p_rate <> 1 THEN
      RAISE_APPLICATION_ERROR(-20002, 'PEN is the base currency: its rate must be 1');
    END IF;
    UPDATE tb_cfg_currency SET currency_name = p_name, exchange_rate_pen = p_rate WHERE currency_id = p_id;
    check_found('Currency', p_id);
  END update_currency;

  PROCEDURE delete_currency (p_id IN NUMBER) IS
  BEGIN
    DELETE FROM tb_cfg_currency WHERE currency_id = p_id;
    check_found('Currency', p_id);
  END delete_currency;

  -- Monto en soles = monto x tasa de la moneda.
  FUNCTION convert_to_pen (p_amount IN NUMBER, p_currency_id IN NUMBER) RETURN NUMBER IS
    v_rate tb_cfg_currency.exchange_rate_pen%TYPE;
  BEGIN
    SELECT exchange_rate_pen INTO v_rate FROM tb_cfg_currency WHERE currency_id = p_currency_id;
    RETURN ROUND(p_amount * v_rate, 2);
  EXCEPTION
    WHEN NO_DATA_FOUND THEN
      RAISE_APPLICATION_ERROR(-20001, 'Currency not found: ' || p_currency_id);
  END convert_to_pen;

  -- ---------------- División y comisaría ----------------
  PROCEDURE insert_division (p_name IN VARCHAR2, p_region IN VARCHAR2, p_id OUT NUMBER) IS
  BEGIN
    p_id := seq_org_division.NEXTVAL;
    INSERT INTO tb_org_division VALUES (p_id, p_name, p_region);
  END insert_division;

  PROCEDURE update_division (p_id IN NUMBER, p_name IN VARCHAR2, p_region IN VARCHAR2) IS
  BEGIN
    UPDATE tb_org_division SET division_name = p_name, region_name = p_region WHERE division_id = p_id;
    check_found('Division', p_id);
  END update_division;

  PROCEDURE delete_division (p_id IN NUMBER) IS
  BEGIN
    DELETE FROM tb_org_division WHERE division_id = p_id;
    check_found('Division', p_id);
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
    check_found('Station', p_id);
  END update_station;

  PROCEDURE delete_station (p_id IN NUMBER) IS
  BEGIN
    DELETE FROM tb_org_station WHERE station_id = p_id;
    check_found('Station', p_id);
  END delete_station;

  -- ---------------- Sector ----------------
  PROCEDURE insert_sector (p_station_id IN NUMBER, p_name IN VARCHAR2,
                           p_min_lat IN NUMBER, p_max_lat IN NUMBER,
                           p_min_lon IN NUMBER, p_max_lon IN NUMBER, p_id OUT NUMBER) IS
  BEGIN
    p_id := seq_terr_sector.NEXTVAL;
    INSERT INTO tb_terr_sector
    VALUES (p_id, p_station_id, p_name, p_min_lat, p_max_lat, p_min_lon, p_max_lon,
            fn_build_rect_polygon(p_min_lat, p_max_lat, p_min_lon, p_max_lon));
  END insert_sector;

  -- Al cambiar la caja se regenera el polígono para que ambos coincidan.
  PROCEDURE update_sector (p_id IN NUMBER, p_station_id IN NUMBER, p_name IN VARCHAR2,
                           p_min_lat IN NUMBER, p_max_lat IN NUMBER,
                           p_min_lon IN NUMBER, p_max_lon IN NUMBER) IS
  BEGIN
    UPDATE tb_terr_sector
       SET station_id = p_station_id, sector_name = p_name,
           min_lat = p_min_lat, max_lat = p_max_lat, min_lon = p_min_lon, max_lon = p_max_lon,
           polygon_area = fn_build_rect_polygon(p_min_lat, p_max_lat, p_min_lon, p_max_lon)
     WHERE sector_id = p_id;
    check_found('Sector', p_id);
  END update_sector;

  PROCEDURE delete_sector (p_id IN NUMBER) IS
  BEGIN
    DELETE FROM tb_terr_sector WHERE sector_id = p_id;
    check_found('Sector', p_id);
  END delete_sector;

  -- Dos filtros en una sola consulta:
  --   1) Caja con intervalo [min, max): un punto sobre el borde de dos sectores pertenece a uno solo.
  --   2) Verificación exacta con el polígono (SDO_ANYINTERACT, usa el índice espacial).
  FUNCTION find_sector_by_location (p_latitude IN NUMBER, p_longitude IN NUMBER) RETURN NUMBER IS
    v_point     SDO_GEOMETRY;
    v_sector_id NUMBER;
  BEGIN
    IF p_latitude NOT BETWEEN -90 AND 90 OR p_longitude NOT BETWEEN -180 AND 180 THEN
      RAISE_APPLICATION_ERROR(-20002, 'Invalid coordinates');
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
    WHEN NO_DATA_FOUND THEN   -- el punto está fuera de todos los sectores
      RETURN NULL;
  END find_sector_by_location;

  -- ---------------- Grado ----------------
  PROCEDURE insert_rank (p_name IN VARCHAR2, p_level IN NUMBER, p_id OUT NUMBER) IS
  BEGIN
    p_id := seq_staff_rank.NEXTVAL;
    INSERT INTO tb_staff_rank VALUES (p_id, p_name, p_level);
  END insert_rank;

  PROCEDURE update_rank (p_id IN NUMBER, p_name IN VARCHAR2, p_level IN NUMBER) IS
  BEGIN
    UPDATE tb_staff_rank SET rank_name = p_name, hierarchy_level = p_level WHERE rank_id = p_id;
    check_found('Rank', p_id);
  END update_rank;

  PROCEDURE delete_rank (p_id IN NUMBER) IS
  BEGIN
    DELETE FROM tb_staff_rank WHERE rank_id = p_id;
    check_found('Rank', p_id);
  END delete_rank;

  -- ---------------- Efectivo ----------------
  -- El contador de casos activos inicia en 0.
  PROCEDURE insert_officer (p_cip IN VARCHAR2, p_first_name IN VARCHAR2, p_last_name IN VARCHAR2,
                            p_rank_id IN NUMBER, p_station_id IN NUMBER,
                            p_supervisor_cip IN VARCHAR2, p_specialty IN VARCHAR2) IS
  BEGIN
    check_supervisor(p_rank_id, p_supervisor_cip);
    INSERT INTO tb_staff_officer
    VALUES (p_cip, p_first_name, p_last_name, p_rank_id, p_station_id, p_supervisor_cip, p_specialty, 0);
  END insert_officer;

  -- También sirve para transferir (station), ascender (rank) o cambiar de superior.
  PROCEDURE update_officer (p_cip IN VARCHAR2, p_first_name IN VARCHAR2, p_last_name IN VARCHAR2,
                            p_rank_id IN NUMBER, p_station_id IN NUMBER,
                            p_supervisor_cip IN VARCHAR2, p_specialty IN VARCHAR2) IS
  BEGIN
    check_supervisor(p_rank_id, p_supervisor_cip);
    UPDATE tb_staff_officer
       SET first_name = p_first_name, last_name = p_last_name, rank_id = p_rank_id,
           station_id = p_station_id, supervisor_cip = p_supervisor_cip, specialty = p_specialty
     WHERE officer_cip = p_cip;
    check_found('Officer', p_cip);
  END update_officer;

  PROCEDURE delete_officer (p_cip IN VARCHAR2) IS
  BEGIN
    DELETE FROM tb_staff_officer WHERE officer_cip = p_cip;
    check_found('Officer', p_cip);
  END delete_officer;

END pkg_org_mgmt;
/
SHOW ERRORS
