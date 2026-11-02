-- ===================================================================
-- GEO-DENUNCIA | Grupo 07 | Modulo INV (Investigacion, Asignacion y Operativos)
-- 04_inv_triggers.sql : limite N de casos activos, contador active_case_count, historial inmutable.
--
-- PRERREQUISITOS (deben existir antes de ejecutar):
--   03_inv_ddl.sql (tablas INV/OPS)
--   TB_STAFF_OFFICER con la columna active_case_count
--   TB_CFG_PARAMETER (el parametro MAX_ACTIVE_CASES lo inserta 05b_inv_data.sql)
--
-- Ejecutar con F5 (Run Script) en SQL Developer.
-- ===================================================================

-- 2.1 Historial inmutable: prohibe UPDATE y DELETE
CREATE OR REPLACE TRIGGER TRG_INV_HISTORY_IMMUTABLE
BEFORE UPDATE OR DELETE ON TB_INV_STATUS_HISTORY
BEGIN
  RAISE_APPLICATION_ERROR(-20010,
    'TB_INV_STATUS_HISTORY es inmutable: no se permite UPDATE ni DELETE.');
END;
/

-- 2.2 Limite N de casos activos (RN-08). Lee N desde TB_CFG_PARAMETER.
--     El SELECT ... FOR UPDATE sobre el oficial serializa asignaciones
--     concurrentes al mismo detective y evita pasarse del limite.
CREATE OR REPLACE TRIGGER TRG_CHECK_MAX_ACTIVE_CASES
BEFORE INSERT ON TB_INV_ASSIGNMENT
FOR EACH ROW
WHEN (NEW.end_date IS NULL)
DECLARE
  v_max   NUMBER;
  v_count NUMBER;
BEGIN
  BEGIN
    SELECT TO_NUMBER(param_value) INTO v_max
      FROM TB_CFG_PARAMETER
     WHERE param_name = 'MAX_ACTIVE_CASES';
  EXCEPTION WHEN NO_DATA_FOUND THEN
    RAISE_APPLICATION_ERROR(-20002, 'Falta el parametro MAX_ACTIVE_CASES en TB_CFG_PARAMETER.');
  END;

  BEGIN
    SELECT NVL(active_case_count, 0) INTO v_count
      FROM TB_STAFF_OFFICER
     WHERE officer_cip = :NEW.officer_cip
       FOR UPDATE;
  EXCEPTION WHEN NO_DATA_FOUND THEN
    RAISE_APPLICATION_ERROR(-20003, 'Oficial inexistente: ' || :NEW.officer_cip);
  END;

  IF v_count >= v_max THEN
    RAISE_APPLICATION_ERROR(-20001,
      'El oficial ' || :NEW.officer_cip || ' alcanzo el limite de ' || v_max ||
      ' casos activos. Asignacion rechazada.');
  END IF;
END;
/

-- 2.3 Mantiene TB_STAFF_OFFICER.active_case_count
--     (tabla distinta a la que dispara el trigger, por eso no hay ORA-04091)
CREATE OR REPLACE TRIGGER TRG_INV_ASSIGN_COUNT
AFTER INSERT OR UPDATE OR DELETE ON TB_INV_ASSIGNMENT
FOR EACH ROW
BEGIN
  IF INSERTING THEN
    IF :NEW.end_date IS NULL THEN
      UPDATE TB_STAFF_OFFICER SET active_case_count = NVL(active_case_count,0) + 1
       WHERE officer_cip = :NEW.officer_cip;
    END IF;
  ELSIF DELETING THEN
    IF :OLD.end_date IS NULL THEN
      UPDATE TB_STAFF_OFFICER SET active_case_count = GREATEST(NVL(active_case_count,0) - 1, 0)
       WHERE officer_cip = :OLD.officer_cip;
    END IF;
  ELSE  -- UPDATING
    IF :OLD.end_date IS NULL THEN
      UPDATE TB_STAFF_OFFICER SET active_case_count = GREATEST(NVL(active_case_count,0) - 1, 0)
       WHERE officer_cip = :OLD.officer_cip;
    END IF;
    IF :NEW.end_date IS NULL THEN
      UPDATE TB_STAFF_OFFICER SET active_case_count = NVL(active_case_count,0) + 1
       WHERE officer_cip = :NEW.officer_cip;
    END IF;
  END IF;
END;
/
