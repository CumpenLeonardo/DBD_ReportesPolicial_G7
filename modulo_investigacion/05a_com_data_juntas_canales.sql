-- ===================================================================
-- GEO-DENUNCIA | Grupo 07 | Modulo INV (Investigacion, Asignacion y Operativos)
-- 05a_com_data_juntas_canales.sql : carga de juntas vecinales y canales de comunicacion.
--
-- PRERREQUISITOS (deben existir antes de ejecutar):
--   Leonardo: TB_TERR_SECTOR (con datos)
--   John    : TB_COM_NEIGHBORHOOD_ASSOC, TB_COM_CHANNEL (DDL)
--
-- IMPORTANTE: ejecutar ANTES de 05_cpl_data.sql de Andy, porque las
-- denuncias referencian a las juntas vecinales.
--
-- Ejecutar con F5 (Run Script) en SQL Developer.
-- ===================================================================

SET SERVEROUTPUT ON;

-- Juntas vecinales y canales (2 juntas por sector, hasta 10 sectores).
-- Es re-ejecutable: no duplica juntas de un sector que ya tiene, y solo agrega
-- canales a las juntas que aun no tienen ninguno.
DECLARE
  TYPE t_names IS TABLE OF VARCHAR2(60);
  v_junta   t_names := t_names('Los Jazmines','San Martin de Porres','Villa Esperanza','Nueva Alianza',
                               'Las Palmeras','Santa Rosa','El Progreso','Mangomarca Unida',
                               'Horizonte','Los Olivos');
  v_canal   t_names := t_names('Grupo de WhatsApp Comunitario','Linea Telefonica Directa',
                               'Radio Tetrapol','Aplicativo Movil');
  v_assoc   NUMBER;
  v_chan    NUMBER;
  v_n       PLS_INTEGER := 0;
  v_cnt     NUMBER;
  v_name    VARCHAR2(100);
  v_type    VARCHAR2(60);
  v_n_junta PLS_INTEGER := v_junta.COUNT;   -- .COUNT no se puede usar dentro de sentencias SQL
  v_n_canal PLS_INTEGER := v_canal.COUNT;
BEGIN
  SELECT NVL(MAX(assoc_id),0)   INTO v_assoc FROM TB_COM_NEIGHBORHOOD_ASSOC;
  SELECT NVL(MAX(channel_id),0) INTO v_chan  FROM TB_COM_CHANNEL;

  FOR s IN (SELECT sector_id FROM TB_TERR_SECTOR
             ORDER BY sector_id FETCH FIRST 10 ROWS ONLY) LOOP
    SELECT COUNT(*) INTO v_cnt FROM TB_COM_NEIGHBORHOOD_ASSOC WHERE sector_id = s.sector_id;
    IF v_cnt = 0 THEN
      FOR j IN 1 .. 2 LOOP
        v_n     := v_n + 1;
        v_assoc := v_assoc + 1;
        v_name  := 'Junta Vecinal ' || v_junta(MOD(v_n - 1, v_n_junta) + 1) || ' ' || j;
        INSERT INTO TB_COM_NEIGHBORHOOD_ASSOC (assoc_id, sector_id, assoc_name)
        VALUES (v_assoc, s.sector_id, v_name);
      END LOOP;
    END IF;
  END LOOP;

  -- Canales: 2 por cada junta que todavia no tenga ninguno
  FOR a IN (SELECT assoc_id FROM TB_COM_NEIGHBORHOOD_ASSOC x
             WHERE NOT EXISTS (SELECT 1 FROM TB_COM_CHANNEL ch WHERE ch.assoc_id = x.assoc_id)
             ORDER BY assoc_id) LOOP
    FOR c IN 1 .. 2 LOOP
      v_chan := v_chan + 1;
      v_type := v_canal(MOD(v_chan + c, v_n_canal) + 1);
      INSERT INTO TB_COM_CHANNEL (channel_id, assoc_id, channel_type)
      VALUES (v_chan, a.assoc_id, v_type);
    END LOOP;
  END LOOP;

  COMMIT;
  IF v_n = 0 THEN
    DBMS_OUTPUT.PUT_LINE('AVISO: no se crearon juntas nuevas (no hay sectores o ya tienen juntas).');
  ELSE
    DBMS_OUTPUT.PUT_LINE('Juntas vecinales creadas: ' || v_n);
  END IF;
END;
/
