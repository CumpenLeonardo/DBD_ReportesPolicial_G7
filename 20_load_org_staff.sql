-- =============================================================================
-- 20_load_org_staff.sql | Ejecutar como GEO_OWNER
-- =============================================================================
-- PROPÓSITO
--   Carga datos ficticios en las 6 tablas base para poder probar el sistema:
--     3 monedas | 2 divisiones | 4 comisarías | 6 sectores | 5 grados | 10 efectivos
--   Nombres, CIP y direcciones son inventados. Las tasas de cambio son
--   referenciales y se actualizan con PKG_ORG_MGMT.update_currency.
--
-- ORDEN DE CARGA
--   Se respeta la dependencia de llaves foráneas: primero las tablas padre
--   (moneda, división, grado), luego las hijas (comisaría, sector, efectivo).
-- =============================================================================
SET DEFINE OFF   -- evita que SQL*Plus interprete el símbolo ampersand en los textos

-- ---- Monedas -----------------------------------------------------------------
-- Columnas: id, código ISO, nombre, soles por unidad. El sol (PEN) es la base.
INSERT INTO tb_cfg_currency VALUES (1, 'PEN', 'Peruvian Sol', 1.0000);
INSERT INTO tb_cfg_currency VALUES (2, 'USD', 'US Dollar',    3.7500);
INSERT INTO tb_cfg_currency VALUES (3, 'EUR', 'Euro',         4.1000);

-- ---- Divisiones policiales (id, nombre, región) --------------------------------
INSERT INTO tb_org_division VALUES (1, 'DIVPOL LIMA ESTE 1 - SJL', 'REGION POLICIAL LIMA');
INSERT INTO tb_org_division VALUES (2, 'DIVPOL LIMA NORTE 1',      'REGION POLICIAL LIMA');

-- ---- Comisarías (id, división, nombre, dirección) -----------------------------
-- Las comisarías 1 y 2 dependen de la división Este y la 3 y 4 de la división Norte.
INSERT INTO tb_org_station VALUES (1, 1, 'COMISARIA CANTO REY',      'Av. Canto Rey 1200, San Juan de Lurigancho');
INSERT INTO tb_org_station VALUES (2, 1, 'COMISARIA SAN HILARION',   'Av. Los Jardines 850, San Juan de Lurigancho');
INSERT INTO tb_org_station VALUES (3, 2, 'COMISARIA LOS OLIVOS',     'Av. Carlos Izaguirre 600, Los Olivos');
INSERT INTO tb_org_station VALUES (4, 2, 'COMISARIA INDEPENDENCIA',  'Av. Tupac Amaru 2100, Independencia');

-- ---- Sectores ------------------------------------------------------------------
-- Cada sector es una caja (min/max latitud y longitud) de 0.01 grados por lado.
-- Las cajas son contiguas y no se superponen: los sectores 1 y 2 son vecinos
-- de oeste a este, y los sectores 1 y 3 comparten el borde en latitud -11.97.
-- Se inserta sin polígono (polygon_area queda NULL) y se genera después.
INSERT INTO tb_terr_sector (sector_id, station_id, sector_name, min_lat, max_lat, min_lon, max_lon)
VALUES (1, 1, 'SECTOR 01 - CANTO REY COMERCIAL',   -11.9800, -11.9700, -77.0000, -76.9900);
INSERT INTO tb_terr_sector (sector_id, station_id, sector_name, min_lat, max_lat, min_lon, max_lon)
VALUES (2, 1, 'SECTOR 02 - CANTO REY RESIDENCIAL', -11.9800, -11.9700, -76.9900, -76.9800);
INSERT INTO tb_terr_sector (sector_id, station_id, sector_name, min_lat, max_lat, min_lon, max_lon)
VALUES (3, 2, 'SECTOR 03 - SAN HILARION NORTE',    -11.9700, -11.9600, -77.0000, -76.9900);
INSERT INTO tb_terr_sector (sector_id, station_id, sector_name, min_lat, max_lat, min_lon, max_lon)
VALUES (4, 2, 'SECTOR 04 - SAN HILARION SUR',      -11.9700, -11.9600, -76.9900, -76.9800);
INSERT INTO tb_terr_sector (sector_id, station_id, sector_name, min_lat, max_lat, min_lon, max_lon)
VALUES (5, 3, 'SECTOR 05 - LOS OLIVOS PANAMERICANA', -11.9700, -11.9600, -77.0800, -77.0700);
INSERT INTO tb_terr_sector (sector_id, station_id, sector_name, min_lat, max_lat, min_lon, max_lon)
VALUES (6, 4, 'SECTOR 06 - INDEPENDENCIA TUPAC AMARU', -11.9900, -11.9800, -77.0600, -77.0500);

-- Genera el polígono geoespacial de todos los sectores a partir de su caja.
UPDATE tb_terr_sector
   SET polygon_area = fn_build_rect_polygon(min_lat, max_lat, min_lon, max_lon);

-- ---- Grados policiales (id, nombre, nivel de mando) ----------------------------
INSERT INTO tb_staff_rank VALUES (1, 'Comandante', 1);
INSERT INTO tb_staff_rank VALUES (2, 'Mayor',      2);
INSERT INTO tb_staff_rank VALUES (3, 'Capitan',    3);
INSERT INTO tb_staff_rank VALUES (4, 'Teniente',   4);
INSERT INTO tb_staff_rank VALUES (5, 'Suboficial', 5);

-- ---- Efectivos -----------------------------------------------------------------
-- Columnas: CIP, nombres, apellidos, grado, comisaría, CIP del superior, especialidad,
-- casos activos. Se insertan primero los superiores porque la llave foránea
-- supervisor_cip exige que el superior ya exista.
-- Jerarquía resultante:
--   Comandante 10000001 (Canto Rey) > Mayores 10000003 y 10000004
--       10000003 > Capitán 10000006 > Teniente 10000008 > Suboficial 10000009
--       10000004 > Capitán 10000007
--   Comandante 10000002 (Los Olivos) > Mayor 10000005 > Suboficial 10000010
INSERT INTO tb_staff_officer VALUES ('10000001', 'Ricardo', 'Salazar Pinto',  1, 1, NULL,       'CRIMINAL_INVESTIGATION', 0);
INSERT INTO tb_staff_officer VALUES ('10000002', 'Maria',   'Quispe Huaman',  1, 3, NULL,       'INTELLIGENCE',           0);
INSERT INTO tb_staff_officer VALUES ('10000003', 'Jorge',   'Paredes Lozano', 2, 1, '10000001', 'CRIMINAL_INVESTIGATION', 0);
INSERT INTO tb_staff_officer VALUES ('10000004', 'Ana',     'Rojas Cardenas', 2, 2, '10000001', 'PUBLIC_ORDER',           0);
INSERT INTO tb_staff_officer VALUES ('10000005', 'Carmen',  'Flores Ortiz',   2, 3, '10000002', 'CRIMINAL_INVESTIGATION', 0);
INSERT INTO tb_staff_officer VALUES ('10000006', 'Daniel',  'Vargas Soto',    3, 1, '10000003', 'CRIMINAL_INVESTIGATION', 0);
INSERT INTO tb_staff_officer VALUES ('10000007', 'Rosa',    'Medina Chavez',  3, 2, '10000004', 'INTELLIGENCE',           0);
INSERT INTO tb_staff_officer VALUES ('10000008', 'Carlos',  'Huaman Diaz',    4, 1, '10000006', 'CRIMINAL_INVESTIGATION', 0);
INSERT INTO tb_staff_officer VALUES ('10000009', 'Jose',    'Quiroz Tello',   5, 1, '10000008', 'CRIMINAL_INVESTIGATION', 0);
INSERT INTO tb_staff_officer VALUES ('10000010', 'Rita',    'Gomez Salas',    5, 3, '10000005', 'PUBLIC_ORDER',           0);

COMMIT;
