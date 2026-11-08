-- =============================================================================
-- 40_grants_roles.sql | Ejecutar como GEO_OWNER cuando ya existan tablas y paquetes
-- Da a cada rol sus permisos. Recorre las tablas y paquetes existentes, así que al
-- agregar los objetos de Andy y John basta con volver a ejecutarlo.
--
--   Rol                Tablas                           Paquetes
--   role_geo_admin     SELECT, INSERT, UPDATE, DELETE   EXECUTE en todos
--   role_geo_chief     SELECT en todas                  ninguno
--   role_geo_operator  SELECT, INSERT, UPDATE (*)       EXECUTE excepto el instalador
--   role_geo_readonly  SELECT (*)                       ninguno
--
-- (*) TB_CPL_COMPLAINT_PROTECTION y TB_CPL_REPORTER guardan la identidad real de los
--     denunciantes anónimos: solo el administrador y los jefes (role_geo_chief) las ven.
--     Registrar denuncias anónimas sigue funcionando porque los paquetes se ejecutan
--     con los derechos de su dueño. La aplicación borra solo a través de los paquetes.
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
