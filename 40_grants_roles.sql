-- =============================================================================
-- 40_grants_roles.sql
-- Permisos de los roles sobre tablas y paquetes, y vista de denunciantes no anónimos.
-- Ejecutar como GEO_OWNER cuando ya existan las tablas y los paquetes.
-- Recorre las tablas y paquetes existentes, por lo que puede volver a ejecutarse.
-- =============================================================================

-- =============================================================================
-- SECCION 1: Permisos por rol
--
--   Rol                Tablas                           Paquetes
--   role_geo_admin     SELECT, INSERT, UPDATE, DELETE   EXECUTE en todos
--   role_geo_chief     SELECT en todas                  ninguno
--   role_geo_operator  SELECT, INSERT, UPDATE (*)       EXECUTE excepto el instalador
--   role_geo_readonly  SELECT (*)                       ninguno
--
-- (*) TB_CPL_COMPLAINT_PROTECTION y TB_CPL_REPORTER revelan la identidad de los denunciantes
--     anónimos y solo las ven role_geo_admin y role_geo_chief. El operador y el rol de consulta
--     leen los denunciantes no anónimos mediante la vista VW_CPL_REPORTER_PUBLIC.
--     El registro de denuncias anónimas funciona porque el paquete se ejecuta con los
--     derechos de su dueño.
-- =============================================================================
BEGIN
  FOR t IN (SELECT table_name FROM user_tables WHERE table_name LIKE 'TB\_%' ESCAPE '\') LOOP
    EXECUTE IMMEDIATE 'GRANT SELECT, INSERT, UPDATE, DELETE ON ' || t.table_name || ' TO role_geo_admin';
    EXECUTE IMMEDIATE 'GRANT SELECT ON ' || t.table_name || ' TO role_geo_chief';
    IF t.table_name NOT IN ('TB_CPL_COMPLAINT_PROTECTION', 'TB_CPL_REPORTER') THEN
      EXECUTE IMMEDIATE 'GRANT SELECT, INSERT, UPDATE ON ' || t.table_name || ' TO role_geo_operator';
      EXECUTE IMMEDIATE 'GRANT SELECT ON ' || t.table_name || ' TO role_geo_readonly';
    END IF;
  END LOOP;

  FOR p IN (SELECT object_name FROM user_objects WHERE object_type = 'PACKAGE') LOOP
    EXECUTE IMMEDIATE 'GRANT EXECUTE ON ' || p.object_name || ' TO role_geo_admin';
    IF p.object_name <> 'PKG_DB_INSTALLER' THEN
      EXECUTE IMMEDIATE 'GRANT EXECUTE ON ' || p.object_name || ' TO role_geo_operator';
    END IF;
  END LOOP;
END;
/

-- =============================================================================
-- SECCION 2: Vista VW_CPL_REPORTER_PUBLIC
-- Lista los denunciantes que no pidieron anonimato: excluye a todo denunciante que figure
-- en TB_CPL_COMPLAINT_PROTECTION, aunque haya presentado otras denuncias firmadas.
-- =============================================================================
CREATE OR REPLACE VIEW vw_cpl_reporter_public AS
SELECT r.*
  FROM tb_cpl_reporter r
 WHERE NOT EXISTS (SELECT 1
                     FROM tb_cpl_complaint_protection p
                    WHERE p.id_reporter = r.id_reporter);

-- Todos los roles pueden consultar la vista (solo lectura).
GRANT SELECT ON vw_cpl_reporter_public TO role_geo_admin;
GRANT SELECT ON vw_cpl_reporter_public TO role_geo_chief;
GRANT SELECT ON vw_cpl_reporter_public TO role_geo_operator;
GRANT SELECT ON vw_cpl_reporter_public TO role_geo_readonly;
