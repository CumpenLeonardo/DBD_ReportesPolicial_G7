-- =============================================================================
-- 20_load_org_staff.sql | Ejecutar como GEO_OWNER
-- Datos ficticios para probar el sistema: 3 monedas, 2 divisiones, 4 comisarías,
-- 6 sectores, 5 grados y 10 efectivos. Las tasas de cambio son referenciales.
-- Se cargan primero las tablas padre y luego las hijas (por las llaves foráneas).
-- =============================================================================
SET DEFINE OFF

-- Monedas: id, código, nombre, soles por unidad (el sol es la base).
INSERT INTO tb_cfg_currency VALUES (1, 'PEN', 'Peruvian Sol', 1.0000);
INSERT INTO tb_cfg_currency VALUES (2, 'USD', 'US Dollar',    3.7500);
INSERT INTO tb_cfg_currency VALUES (3, 'EUR', 'Euro',         4.1000);

-- Divisiones: id, nombre, región.
INSERT INTO tb_org_division VALUES (1, 'DIVPOL LIMA ESTE 1 - SJL', 'REGION POLICIAL LIMA');
INSERT INTO tb_org_division VALUES (2, 'DIVPOL LIMA NORTE 1',      'REGION POLICIAL LIMA');

-- Comisarías: id, división, nombre, dirección.
INSERT INTO tb_org_station VALUES (1, 1, 'COMISARIA CANTO REY',     'Av. Canto Rey 1200, San Juan de Lurigancho');
INSERT INTO tb_org_station VALUES (2, 1, 'COMISARIA SAN HILARION',  'Av. Los Jardines 850, San Juan de Lurigancho');
INSERT INTO tb_org_station VALUES (3, 2, 'COMISARIA LOS OLIVOS',    'Av. Carlos Izaguirre 600, Los Olivos');
INSERT INTO tb_org_station VALUES (4, 2, 'COMISARIA INDEPENDENCIA', 'Av. Tupac Amaru 2100, Independencia');

-- Sectores: cajas contiguas de 0.01 grados que no se superponen. Los sectores 1 y 3
-- comparten el borde en latitud -11.97. El polígono se genera luego con un UPDATE.
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
   SET polygon_area = fn_build_rect_polygon(min_lat, max_lat, min_lon, max_lon);

-- Grados: id, nombre, nivel de mando (1 = superior).
INSERT INTO tb_staff_rank VALUES (1, 'Comandante', 1);
INSERT INTO tb_staff_rank VALUES (2, 'Mayor',      2);
INSERT INTO tb_staff_rank VALUES (3, 'Capitan',    3);
INSERT INTO tb_staff_rank VALUES (4, 'Teniente',   4);
INSERT INTO tb_staff_rank VALUES (5, 'Suboficial', 5);

-- Efectivos: CIP, nombres, apellidos, grado, comisaría, CIP del superior, especialidad,
-- casos activos. Los superiores se insertan primero porque la FK exige que ya existan.
--   10000001 Comandante > 10000003 Mayor > 10000006 Capitan > 10000008 Teniente > 10000009 Suboficial
--   10000001 Comandante > 10000004 Mayor > 10000007 Capitan
--   10000002 Comandante > 10000005 Mayor > 10000010 Suboficial
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
