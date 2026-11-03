-- =============================================================================
-- 30_pkg_org_mgmt.sql | Ejecutar como GEO_OWNER
-- =============================================================================
-- PAQUETE: PKG_ORG_MGMT
-- PROPÓSITO
--   Concentra todo el acceso a las 6 tablas base del sistema (moneda, división,
--   comisaría, sector, grado y efectivo) y la lógica de negocio asociada. La
--   aplicación Java debe usar este paquete en vez de ejecutar INSERT/UPDATE/DELETE
--   directos, para que las reglas se apliquen siempre.
--
-- CONTENIDO
--   CRUD (por cada tabla)   insert_*  crea y devuelve el ID generado (parámetro OUT)
--                           update_*  modifica un registro por su ID
--                           delete_*  elimina un registro por su ID
--                           get_*     devuelve el registro como SYS_REFCURSOR
--   Lógica de negocio       convert_to_pen, find_sector_by_location,
--                           validación de jerarquía en efectivos
--   Reporte                 report_station_staffing (cursores explícitos)
--
-- CONVENCIONES
--   * Errores propios: -20001 registro no encontrado | -20002 dato inválido.
--     Los errores de llaves foráneas (ORA-02292, ORA-02291) se dejan pasar tal cual.
--   * El paquete no hace COMMIT: la transacción la controla quien lo llama
--     (script de pruebas o aplicación Java).
-- =============================================================================

-- -----------------------------------------------------------------------------
-- ESPECIFICACIÓN: lista de subprogramas públicos (lo que otros pueden invocar)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE PACKAGE pkg_org_mgmt AS

  -- ===== Moneda (TB_CFG_CURRENCY) =====
  -- Crea una moneda. El código se guarda en mayúsculas. Devuelve el nuevo ID en p_id.
  PROCEDURE insert_currency (p_code IN VARCHAR2, p_name IN VARCHAR2, p_rate IN NUMBER, p_id OUT NUMBER);
  -- Cambia nombre y tasa de cambio. Regla: la moneda base PEN (id 1) siempre vale 1.
  PROCEDURE update_currency (p_id IN NUMBER, p_name IN VARCHAR2, p_rate IN NUMBER);
  PROCEDURE delete_currency (p_id IN NUMBER);
  FUNCTION  get_currency    (p_id IN NUMBER) RETURN SYS_REFCURSOR;
  -- Convierte un monto a soles con la tasa vigente de la moneda y redondea a 2 decimales.
  -- La usarán las denuncias para calcular amount_pen.
  FUNCTION  convert_to_pen  (p_amount IN NUMBER, p_currency_id IN NUMBER) RETURN NUMBER;

  -- ===== División policial (TB_ORG_DIVISION) =====
  PROCEDURE insert_division (p_name IN VARCHAR2, p_region IN VARCHAR2, p_id OUT NUMBER);
  PROCEDURE update_division (p_id IN NUMBER, p_name IN VARCHAR2, p_region IN VARCHAR2);
  PROCEDURE delete_division (p_id IN NUMBER);
  FUNCTION  get_division    (p_id IN NUMBER) RETURN SYS_REFCURSOR;

  -- ===== Comisaría (TB_ORG_STATION) =====
  PROCEDURE insert_station (p_division_id IN NUMBER, p_name IN VARCHAR2, p_address IN VARCHAR2, p_id OUT NUMBER);
  PROCEDURE update_station (p_id IN NUMBER, p_division_id IN NUMBER, p_name IN VARCHAR2, p_address IN VARCHAR2);
  PROCEDURE delete_station (p_id IN NUMBER);
  FUNCTION  get_station    (p_id IN NUMBER) RETURN SYS_REFCURSOR;

  -- ===== Sector (TB_TERR_SECTOR) =====
  -- Al crear o modificar un sector solo se informa su bounding box: el polígono
  -- geoespacial se construye automáticamente a partir de él.
  PROCEDURE insert_sector (p_station_id IN NUMBER, p_name IN VARCHAR2,
                           p_min_lat IN NUMBER, p_max_lat IN NUMBER,
                           p_min_lon IN NUMBER, p_max_lon IN NUMBER, p_id OUT NUMBER);
  PROCEDURE update_sector (p_id IN NUMBER, p_station_id IN NUMBER, p_name IN VARCHAR2,
                           p_min_lat IN NUMBER, p_max_lat IN NUMBER,
                           p_min_lon IN NUMBER, p_max_lon IN NUMBER);
  PROCEDURE delete_sector (p_id IN NUMBER);
  FUNCTION  get_sector    (p_id IN NUMBER) RETURN SYS_REFCURSOR;
  -- Asignación automática de sector: recibe el punto GPS de un incidente y devuelve
  -- el ID del sector que lo contiene, o NULL si el punto está fuera de todos los sectores.
  FUNCTION  find_sector_by_location (p_latitude IN NUMBER, p_longitude IN NUMBER) RETURN NUMBER;

  -- ===== Grado policial (TB_STAFF_RANK) =====
  PROCEDURE insert_rank (p_name IN VARCHAR2, p_level IN NUMBER, p_id OUT NUMBER);
  PROCEDURE update_rank (p_id IN NUMBER, p_name IN VARCHAR2, p_level IN NUMBER);
  PROCEDURE delete_rank (p_id IN NUMBER);
  FUNCTION  get_rank    (p_id IN NUMBER) RETURN SYS_REFCURSOR;

  -- ===== Efectivo policial (TB_STAFF_OFFICER) =====
  -- Regla de negocio: el superior directo debe tener un grado mayor que el efectivo.
  -- Esa regla también evita ciclos de mando (A supervisa a B y B supervisa a A).
  -- No se recibe active_case_count: lo administra el trigger del límite de casos.
  PROCEDURE insert_officer (p_cip IN VARCHAR2, p_first_name IN VARCHAR2, p_last_name IN VARCHAR2,
                            p_rank_id IN NUMBER, p_station_id IN NUMBER,
                            p_supervisor_cip IN VARCHAR2, p_specialty IN VARCHAR2);
  PROCEDURE update_officer (p_cip IN VARCHAR2, p_first_name IN VARCHAR2, p_last_name IN VARCHAR2,
                            p_rank_id IN NUMBER, p_station_id IN NUMBER,
                            p_supervisor_cip IN VARCHAR2, p_specialty IN VARCHAR2);
  PROCEDURE delete_officer (p_cip IN VARCHAR2);
  FUNCTION  get_officer    (p_cip IN VARCHAR2) RETURN SYS_REFCURSOR;

  -- ===== Reporte =====
  -- Imprime con DBMS_OUTPUT, por comisaría, cuántos efectivos hay de cada grado.
  -- Si p_station_id es NULL, reporta todas las comisarías.
  PROCEDURE report_station_staffing (p_station_id IN NUMBER DEFAULT NULL);

END pkg_org_mgmt;
/

-- -----------------------------------------------------------------------------
-- CUERPO: implementación
-- -----------------------------------------------------------------------------
CREATE OR REPLACE PACKAGE BODY pkg_org_mgmt AS

  -- ---------------- Subprogramas privados (solo los usa este paquete) ----------------

  -- Se invoca justo después de un UPDATE o DELETE. Si no se afectó ninguna fila
  -- significa que el ID no existe, y se lanza el error -20001.
  PROCEDURE check_found (p_entity IN VARCHAR2, p_key IN VARCHAR2) IS
  BEGIN
    IF SQL%ROWCOUNT = 0 THEN
      RAISE_APPLICATION_ERROR(-20001, p_entity || ' not found: ' || p_key);
    END IF;
  END check_found;

  -- Valida la regla de jerarquía policial: compara el nivel del grado del superior
  -- con el del efectivo. Un nivel menor es un grado más alto, así que el superior
  -- debe tener un nivel estrictamente menor. Si no hay superior (NULL) no valida nada.
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
    WHEN NO_DATA_FOUND THEN   -- el superior o el grado indicado no existen
      RAISE_APPLICATION_ERROR(-20001, 'Supervisor or rank not found');
  END check_supervisor;

  -- ---------------- Moneda ----------------
  PROCEDURE insert_currency (p_code IN VARCHAR2, p_name IN VARCHAR2, p_rate IN NUMBER, p_id OUT NUMBER) IS
  BEGIN
    p_id := seq_cfg_currency.NEXTVAL;   -- ID automático desde la secuencia
    INSERT INTO tb_cfg_currency VALUES (p_id, UPPER(p_code), p_name, p_rate);
  END insert_currency;

  PROCEDURE update_currency (p_id IN NUMBER, p_name IN VARCHAR2, p_rate IN NUMBER) IS
  BEGIN
    -- La moneda base (PEN, id 1) siempre convierte 1 a 1: no se permite alterarla.
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

  FUNCTION get_currency (p_id IN NUMBER) RETURN SYS_REFCURSOR IS
    v_cur SYS_REFCURSOR;
  BEGIN
    OPEN v_cur FOR SELECT * FROM tb_cfg_currency WHERE currency_id = p_id;
    RETURN v_cur;
  END get_currency;

  -- Monto en soles = monto original x tasa de la moneda, redondeado a 2 decimales.
  FUNCTION convert_to_pen (p_amount IN NUMBER, p_currency_id IN NUMBER) RETURN NUMBER IS
    v_rate tb_cfg_currency.exchange_rate_pen%TYPE;
  BEGIN
    SELECT exchange_rate_pen INTO v_rate FROM tb_cfg_currency WHERE currency_id = p_currency_id;
    RETURN ROUND(p_amount * v_rate, 2);
  EXCEPTION
    WHEN NO_DATA_FOUND THEN
      RAISE_APPLICATION_ERROR(-20001, 'Currency not found: ' || p_currency_id);
  END convert_to_pen;

  -- ---------------- División ----------------
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

  FUNCTION get_division (p_id IN NUMBER) RETURN SYS_REFCURSOR IS
    v_cur SYS_REFCURSOR;
  BEGIN
    OPEN v_cur FOR SELECT * FROM tb_org_division WHERE division_id = p_id;
    RETURN v_cur;
  END get_division;

  -- ---------------- Comisaría ----------------
  PROCEDURE insert_station (p_division_id IN NUMBER, p_name IN VARCHAR2, p_address IN VARCHAR2, p_id OUT NUMBER) IS
  BEGIN
    p_id := seq_org_station.NEXTVAL;
    INSERT INTO tb_org_station VALUES (p_id, p_division_id, p_name, p_address);
  END insert_station;

  PROCEDURE update_station (p_id IN NUMBER, p_division_id IN NUMBER, p_name IN VARCHAR2, p_address IN VARCHAR2) IS
  BEGIN
    UPDATE tb_org_station
       SET division_id = p_division_id, station_name = p_name, address = p_address
     WHERE station_id = p_id;
    check_found('Station', p_id);
  END update_station;

  PROCEDURE delete_station (p_id IN NUMBER) IS
  BEGIN
    DELETE FROM tb_org_station WHERE station_id = p_id;
    check_found('Station', p_id);
  END delete_station;

  FUNCTION get_station (p_id IN NUMBER) RETURN SYS_REFCURSOR IS
    v_cur SYS_REFCURSOR;
  BEGIN
    OPEN v_cur FOR SELECT * FROM tb_org_station WHERE station_id = p_id;
    RETURN v_cur;
  END get_station;

  -- ---------------- Sector ----------------
  -- El polígono se arma con fn_build_rect_polygon a partir de las 4 coordenadas.
  PROCEDURE insert_sector (p_station_id IN NUMBER, p_name IN VARCHAR2,
                           p_min_lat IN NUMBER, p_max_lat IN NUMBER,
                           p_min_lon IN NUMBER, p_max_lon IN NUMBER, p_id OUT NUMBER) IS
  BEGIN
    p_id := seq_terr_sector.NEXTVAL;
    INSERT INTO tb_terr_sector
    VALUES (p_id, p_station_id, p_name, p_min_lat, p_max_lat, p_min_lon, p_max_lon,
            fn_build_rect_polygon(p_min_lat, p_max_lat, p_min_lon, p_max_lon));
  END insert_sector;

  -- Al cambiar la caja también se regenera el polígono para que ambos coincidan.
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

  FUNCTION get_sector (p_id IN NUMBER) RETURN SYS_REFCURSOR IS
    v_cur SYS_REFCURSOR;
  BEGIN
    OPEN v_cur FOR SELECT * FROM tb_terr_sector WHERE sector_id = p_id;
    RETURN v_cur;
  END get_sector;

  -- Asignación de sector por GPS en dos pasos dentro de una sola consulta:
  --   1) Filtro rápido por bounding box. Se usa el intervalo semiabierto [min, max):
  --      un punto exactamente sobre el borde compartido por dos sectores pertenece
  --      a uno solo, el de arriba o la derecha, y nunca queda ambiguo.
  --   2) Verificación exacta con Oracle Spatial (SDO_ANYINTERACT) contra el polígono.
  -- Si ningún sector contiene el punto, devuelve NULL (la denuncia queda sin sector).
  FUNCTION find_sector_by_location (p_latitude IN NUMBER, p_longitude IN NUMBER) RETURN NUMBER IS
    v_point     SDO_GEOMETRY;
    v_sector_id NUMBER;
  BEGIN
    IF p_latitude NOT BETWEEN -90 AND 90 OR p_longitude NOT BETWEEN -180 AND 180 THEN
      RAISE_APPLICATION_ERROR(-20002, 'Invalid coordinates');
    END IF;
    -- Punto GPS como geometría (x = longitud, y = latitud, SRID 4326).
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

  FUNCTION get_rank (p_id IN NUMBER) RETURN SYS_REFCURSOR IS
    v_cur SYS_REFCURSOR;
  BEGIN
    OPEN v_cur FOR SELECT * FROM tb_staff_rank WHERE rank_id = p_id;
    RETURN v_cur;
  END get_rank;

  -- ---------------- Efectivo ----------------
  -- Antes de insertar o actualizar se valida la jerarquía (check_supervisor).
  -- Al crearlo, el contador de casos activos inicia en 0.
  PROCEDURE insert_officer (p_cip IN VARCHAR2, p_first_name IN VARCHAR2, p_last_name IN VARCHAR2,
                            p_rank_id IN NUMBER, p_station_id IN NUMBER,
                            p_supervisor_cip IN VARCHAR2, p_specialty IN VARCHAR2) IS
  BEGIN
    check_supervisor(p_rank_id, p_supervisor_cip);
    INSERT INTO tb_staff_officer
    VALUES (p_cip, p_first_name, p_last_name, p_rank_id, p_station_id, p_supervisor_cip, p_specialty, 0);
  END insert_officer;

  -- Sirve también para transferir al efectivo (cambiar p_station_id), ascenderlo
  -- (cambiar p_rank_id) o reasignarle superior (cambiar p_supervisor_cip).
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

  FUNCTION get_officer (p_cip IN VARCHAR2) RETURN SYS_REFCURSOR IS
    v_cur SYS_REFCURSOR;
  BEGIN
    OPEN v_cur FOR SELECT * FROM tb_staff_officer WHERE officer_cip = p_cip;
    RETURN v_cur;
  END get_officer;

  -- ---------------- Reporte ----------------
  -- Reporte de dotación por comisaría. Usa dos cursores explícitos anidados
  -- (OPEN, FETCH, EXIT WHEN %NOTFOUND, CLOSE):
  --   c_stations  recorre las comisarías (una o todas según el parámetro).
  --   c_ranks     para cada comisaría cuenta los efectivos por grado. El LEFT JOIN
  --               hace que aparezcan también los grados con 0 efectivos.
  PROCEDURE report_station_staffing (p_station_id IN NUMBER DEFAULT NULL) IS
    CURSOR c_stations (cp_station_id NUMBER) IS
      SELECT station_id, station_name
        FROM tb_org_station
       WHERE cp_station_id IS NULL OR station_id = cp_station_id
       ORDER BY station_name;

    CURSOR c_ranks (cp_station_id NUMBER) IS
      SELECT r.rank_name, COUNT(o.officer_cip) AS total
        FROM tb_staff_rank r
        LEFT JOIN tb_staff_officer o ON o.rank_id = r.rank_id AND o.station_id = cp_station_id
       GROUP BY r.rank_name, r.hierarchy_level
       ORDER BY r.hierarchy_level;

    v_station c_stations%ROWTYPE;
    v_rank    c_ranks%ROWTYPE;
  BEGIN
    OPEN c_stations(p_station_id);
    LOOP
      FETCH c_stations INTO v_station;
      EXIT WHEN c_stations%NOTFOUND;
      DBMS_OUTPUT.PUT_LINE(v_station.station_name);
      OPEN c_ranks(v_station.station_id);
      LOOP
        FETCH c_ranks INTO v_rank;
        EXIT WHEN c_ranks%NOTFOUND;
        DBMS_OUTPUT.PUT_LINE('   ' || RPAD(v_rank.rank_name, 12) || v_rank.total);
      END LOOP;
      CLOSE c_ranks;
    END LOOP;
    CLOSE c_stations;
  END report_station_staffing;

END pkg_org_mgmt;
/
SHOW ERRORS
