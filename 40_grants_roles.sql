-- =============================================================================
-- 40_grants_roles.sql | Ejecutar como GEO_OWNER cuando ya existan tablas y paquetes
-- =============================================================================
-- PROPÓSITO
--   Otorga a cada rol los permisos que le corresponden sobre las tablas y
--   paquetes del esquema (los roles se crearon en 01_security_setup.sql).
--
-- MATRIZ DE PERMISOS
--   Rol                Tablas (TB_*)                       Paquetes
--   role_geo_admin     SELECT, INSERT, UPDATE, DELETE      EXECUTE en todos
--   role_geo_operator  SELECT, INSERT, UPDATE              EXECUTE excepto el instalador
--   role_geo_readonly  SELECT                              ninguno
--
-- Recorre dinámicamente todas las tablas y paquetes existentes, así que al agregar
-- los objetos de Andy y John basta con volver a ejecutar este script.
-- El operador no recibe DELETE directo: la aplicación borra solo a través de los
-- procedimientos de los paquetes (se ejecutan con los derechos de su dueño).
-- El instalador (que borra todo el esquema) queda restringido al administrador.
-- =============================================================================
BEGIN
  -- Permisos sobre tablas
  FOR t IN (SELECT table_name FROM user_tables WHERE table_name LIKE 'TB\_%' ESCAPE '\') LOOP
    EXECUTE IMMEDIATE 'GRANT SELECT, INSERT, UPDATE, DELETE ON ' || t.table_name || ' TO role_geo_admin';
    EXECUTE IMMEDIATE 'GRANT SELECT, INSERT, UPDATE ON '         || t.table_name || ' TO role_geo_operator';
    EXECUTE IMMEDIATE 'GRANT SELECT ON '                          || t.table_name || ' TO role_geo_readonly';
  END LOOP;

  -- Permisos de ejecución sobre paquetes
  FOR p IN (SELECT object_name FROM user_objects WHERE object_type = 'PACKAGE') LOOP
    EXECUTE IMMEDIATE 'GRANT EXECUTE ON ' || p.object_name || ' TO role_geo_admin';
    IF p.object_name <> 'PKG_DB_INSTALLER' THEN
      EXECUTE IMMEDIATE 'GRANT EXECUTE ON ' || p.object_name || ' TO role_geo_operator';
    END IF;
  END LOOP;
END;
/
