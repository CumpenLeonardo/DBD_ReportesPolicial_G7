-- ===================================================================
-- GEO-DENUNCIA | Grupo 07 | Modulo INV (Investigacion, Asignacion y Operativos)
-- 06_pkg_inv_mgmt.sql : paquete PKG_INV_MGMT (CRUD, change_status, assign_investigator, register_operation).
--
-- PRERREQUISITOS (deben existir antes de ejecutar):
--   03_inv_ddl.sql y 04_inv_triggers.sql
--   Andy: TB_CPL_COMPLAINT (current_status, sector_id)
--   Leonardo: TB_STAFF_OFFICER
--
-- Ejecutar con F5 (Run Script) en SQL Developer.
-- ===================================================================

CREATE OR REPLACE PACKAGE PKG_INV_MGMT AS

  TYPE t_id_list  IS TABLE OF NUMBER;
  TYPE t_cip_list IS TABLE OF VARCHAR2(15);

  -- Estados
  c_registrado        CONSTANT VARCHAR2(30) := 'REGISTRADO';
  c_validado          CONSTANT VARCHAR2(30) := 'VALIDADO_COMISARIA';
  c_en_investigacion  CONSTANT VARCHAR2(30) := 'EN_INVESTIGACION';
  c_intervencion      CONSTANT VARCHAR2(30) := 'INTERVENCION_PROGRAMADA';
  c_derivado          CONSTANT VARCHAR2(30) := 'DERIVADO_FISCALIA';
  c_archivado         CONSTANT VARCHAR2(30) := 'ARCHIVADO';
  c_resuelto          CONSTANT VARCHAR2(30) := 'RESUELTO';

  c_min_reason_len    CONSTANT PLS_INTEGER := 10;

  -- Codigos de error
  c_err_reason_required  CONSTANT PLS_INTEGER := -20020;
  c_err_bad_transition   CONSTANT PLS_INTEGER := -20021;
  c_err_not_found        CONSTANT PLS_INTEGER := -20022;
  c_err_no_assignment    CONSTANT PLS_INTEGER := -20023;
  c_err_bad_status       CONSTANT PLS_INTEGER := -20031;
  c_err_same_officer     CONSTANT PLS_INTEGER := -20032;
  c_err_reassign_reason  CONSTANT PLS_INTEGER := -20033;
  c_err_operation        CONSTANT PLS_INTEGER := -20040;
  c_err_active_assign    CONSTANT PLS_INTEGER := -20050;

  -- Reglas de estado
  FUNCTION is_valid_transition(p_from IN VARCHAR2, p_to IN VARCHAR2) RETURN BOOLEAN;

  PROCEDURE log_initial_status(p_complaint_id IN NUMBER, p_officer_cip IN VARCHAR2,
                               p_reason IN VARCHAR2 DEFAULT 'Denuncia registrada en el sistema');

  PROCEDURE change_status(p_complaint_id IN NUMBER, p_new_status IN VARCHAR2,
                          p_officer_cip IN VARCHAR2, p_reason IN VARCHAR2);

  -- Asignacion
  FUNCTION assign_investigator(p_complaint_id    IN NUMBER,
                               p_officer_cip     IN VARCHAR2,
                               p_assigned_by_cip IN VARCHAR2,
                               p_reason          IN VARCHAR2 DEFAULT NULL) RETURN NUMBER;
  PROCEDURE close_assignment(p_assignment_id IN NUMBER, p_reason IN VARCHAR2);
  PROCEDURE update_assignment_reason(p_assignment_id IN NUMBER, p_reason IN VARCHAR2);
  PROCEDURE delete_assignment(p_assignment_id IN NUMBER);
  FUNCTION  get_assignments(p_complaint_id IN NUMBER) RETURN SYS_REFCURSOR;
  PROCEDURE recalc_active_case_count;

  -- Equipo de apoyo
  PROCEDURE add_support_member(p_complaint_id IN NUMBER, p_officer_cip IN VARCHAR2);
  PROCEDURE remove_support_member(p_complaint_id IN NUMBER, p_officer_cip IN VARCHAR2);
  FUNCTION  get_support_team(p_complaint_id IN NUMBER) RETURN SYS_REFCURSOR;

  -- Historial (solo lectura: es inmutable)
  FUNCTION  get_status_history(p_complaint_id IN NUMBER) RETURN SYS_REFCURSOR;

  -- Operativos
  FUNCTION  create_operation(p_sector_id IN NUMBER, p_operation_type IN VARCHAR2,
                             p_operation_date IN TIMESTAMP) RETURN NUMBER;
  PROCEDURE update_operation(p_operation_id IN NUMBER, p_sector_id IN NUMBER,
                             p_operation_type IN VARCHAR2, p_operation_date IN TIMESTAMP);
  PROCEDURE delete_operation(p_operation_id IN NUMBER);   -- borra en cascada sus relaciones
  PROCEDURE link_complaint(p_operation_id IN NUMBER, p_complaint_id IN NUMBER);
  PROCEDURE unlink_complaint(p_operation_id IN NUMBER, p_complaint_id IN NUMBER);
  PROCEDURE add_operation_staff(p_operation_id IN NUMBER, p_officer_cip IN VARCHAR2);
  PROCEDURE remove_operation_staff(p_operation_id IN NUMBER, p_officer_cip IN VARCHAR2);
  FUNCTION  get_operation(p_operation_id IN NUMBER) RETURN SYS_REFCURSOR;

  -- P10: registro de operativo multidenuncia (cabecera + denuncias + efectivos)
  FUNCTION register_operation(p_sector_id      IN NUMBER,
                              p_operation_type IN VARCHAR2,
                              p_operation_date IN TIMESTAMP,
                              p_complaints     IN t_id_list,
                              p_staff          IN t_cip_list) RETURN NUMBER;
END PKG_INV_MGMT;
/

CREATE OR REPLACE PACKAGE BODY PKG_INV_MGMT AS

  ---------------------------------------------------------------- privados
  FUNCTION lock_complaint_status(p_complaint_id IN NUMBER) RETURN VARCHAR2 IS
    v_status TB_CPL_COMPLAINT.current_status%TYPE;
  BEGIN
    SELECT current_status INTO v_status
      FROM TB_CPL_COMPLAINT
     WHERE complaint_id = p_complaint_id
       FOR UPDATE;
    RETURN v_status;
  EXCEPTION WHEN NO_DATA_FOUND THEN
    RAISE_APPLICATION_ERROR(c_err_not_found, 'Denuncia inexistente: ' || p_complaint_id);
  END lock_complaint_status;

  PROCEDURE assert_officer_exists(p_cip IN VARCHAR2) IS
    v_cnt NUMBER;
  BEGIN
    SELECT COUNT(*) INTO v_cnt FROM TB_STAFF_OFFICER WHERE officer_cip = p_cip;
    IF v_cnt = 0 THEN
      RAISE_APPLICATION_ERROR(c_err_not_found, 'Oficial inexistente: ' || p_cip);
    END IF;
  END assert_officer_exists;

  ------------------------------------------------------------ reglas estado
  FUNCTION is_valid_transition(p_from IN VARCHAR2, p_to IN VARCHAR2) RETURN BOOLEAN IS
  BEGIN
    IF p_from IS NULL THEN
      RETURN p_to = c_registrado;
    ELSIF p_from = c_registrado THEN
      RETURN p_to = c_validado;
    ELSIF p_from = c_validado THEN
      RETURN p_to = c_en_investigacion;
    ELSIF p_from = c_en_investigacion THEN
      RETURN p_to IN (c_intervencion, c_derivado, c_archivado, c_resuelto);
    ELSIF p_from = c_intervencion THEN
      RETURN p_to IN (c_en_investigacion, c_derivado, c_archivado, c_resuelto);
    ELSIF p_from = c_derivado THEN
      RETURN p_to IN (c_archivado, c_resuelto);
    END IF;
    RETURN FALSE;   -- ARCHIVADO y RESUELTO son estados terminales
  END is_valid_transition;

  PROCEDURE log_initial_status(p_complaint_id IN NUMBER, p_officer_cip IN VARCHAR2,
                               p_reason IN VARCHAR2 DEFAULT 'Denuncia registrada en el sistema') IS
  BEGIN
    assert_officer_exists(p_officer_cip);
    INSERT INTO TB_INV_STATUS_HISTORY
      (complaint_id, officer_cip, previous_status, new_status, change_reason)
    VALUES
      (p_complaint_id, p_officer_cip, NULL, c_registrado, p_reason);
  END log_initial_status;

  PROCEDURE change_status(p_complaint_id IN NUMBER, p_new_status IN VARCHAR2,
                          p_officer_cip IN VARCHAR2, p_reason IN VARCHAR2) IS
    v_prev TB_CPL_COMPLAINT.current_status%TYPE;
    v_cnt  NUMBER;
  BEGIN
    IF p_reason IS NULL OR LENGTH(TRIM(p_reason)) < c_min_reason_len THEN
      RAISE_APPLICATION_ERROR(c_err_reason_required,
        'Las observaciones/motivo son obligatorias (minimo ' || c_min_reason_len || ' caracteres).');
    END IF;

    assert_officer_exists(p_officer_cip);
    v_prev := lock_complaint_status(p_complaint_id);

    IF NOT is_valid_transition(v_prev, p_new_status) THEN
      RAISE_APPLICATION_ERROR(c_err_bad_transition,
        'Transicion no permitida: ' || NVL(v_prev,'(sin estado)') || ' -> ' || NVL(p_new_status,'NULL'));
    END IF;

    IF p_new_status = c_en_investigacion THEN
      SELECT COUNT(*) INTO v_cnt
        FROM TB_INV_ASSIGNMENT
       WHERE complaint_id = p_complaint_id AND end_date IS NULL;
      IF v_cnt = 0 THEN
        RAISE_APPLICATION_ERROR(c_err_no_assignment,
          'No se puede pasar a EN_INVESTIGACION sin un investigador titular activo.');
      END IF;
    END IF;

    INSERT INTO TB_INV_STATUS_HISTORY
      (complaint_id, officer_cip, previous_status, new_status, change_reason)
    VALUES
      (p_complaint_id, p_officer_cip, v_prev, p_new_status, SUBSTR(TRIM(p_reason), 1, 300));

    UPDATE TB_CPL_COMPLAINT
       SET current_status = p_new_status
     WHERE complaint_id = p_complaint_id;

    -- Al cerrar el caso se libera el cupo del investigador
    IF p_new_status IN (c_archivado, c_resuelto) THEN
      UPDATE TB_INV_ASSIGNMENT
         SET end_date = SYSDATE
       WHERE complaint_id = p_complaint_id AND end_date IS NULL;
    END IF;
  END change_status;

  ------------------------------------------------------------- asignacion
  FUNCTION assign_investigator(p_complaint_id    IN NUMBER,
                               p_officer_cip     IN VARCHAR2,
                               p_assigned_by_cip IN VARCHAR2,
                               p_reason          IN VARCHAR2 DEFAULT NULL) RETURN NUMBER IS
    v_status    TB_CPL_COMPLAINT.current_status%TYPE;
    v_active_id NUMBER;
    v_active_by VARCHAR2(15);
    v_new_id    NUMBER;
  BEGIN
    SAVEPOINT sp_assign;

    IF p_officer_cip = p_assigned_by_cip THEN
      RAISE_APPLICATION_ERROR(c_err_same_officer,
        'El investigador no puede ser quien firma la asignacion.');
    END IF;
    assert_officer_exists(p_officer_cip);
    assert_officer_exists(p_assigned_by_cip);

    v_status := lock_complaint_status(p_complaint_id);
    IF v_status NOT IN (c_validado, c_en_investigacion, c_intervencion) THEN
      RAISE_APPLICATION_ERROR(c_err_bad_status,
        'Solo se asigna en VALIDADO_COMISARIA o se reasigna en EN_INVESTIGACION/INTERVENCION_PROGRAMADA. Estado actual: '
        || NVL(v_status,'NULL'));
    END IF;

    BEGIN
      SELECT assignment_id INTO v_active_id
        FROM TB_INV_ASSIGNMENT
       WHERE complaint_id = p_complaint_id AND end_date IS NULL
         FOR UPDATE;
      SELECT officer_cip INTO v_active_by FROM TB_INV_ASSIGNMENT WHERE assignment_id = v_active_id;
    EXCEPTION WHEN NO_DATA_FOUND THEN
      v_active_id := NULL;
    END;

    IF v_active_id IS NOT NULL THEN
      IF v_active_by = p_officer_cip THEN
        RAISE_APPLICATION_ERROR(c_err_same_officer, 'El oficial ya es el titular del caso.');
      END IF;
      IF p_reason IS NULL OR LENGTH(TRIM(p_reason)) < c_min_reason_len THEN
        RAISE_APPLICATION_ERROR(c_err_reassign_reason,
          'La reasignacion exige un motivo (minimo ' || c_min_reason_len || ' caracteres).');
      END IF;
      UPDATE TB_INV_ASSIGNMENT
         SET end_date = SYSDATE,
             reassignment_reason = SUBSTR(TRIM(p_reason), 1, 200)
       WHERE assignment_id = v_active_id;
    ELSIF v_status <> c_validado THEN
      RAISE_APPLICATION_ERROR(c_err_bad_status,
        'El caso esta en ' || v_status || ' pero no tiene titular activo; revise la integridad.');
    END IF;

    -- El trigger TRG_CHECK_MAX_ACTIVE_CASES valida el limite N en este INSERT
    INSERT INTO TB_INV_ASSIGNMENT (complaint_id, officer_cip, assigned_by_cip)
    VALUES (p_complaint_id, p_officer_cip, p_assigned_by_cip)
    RETURNING assignment_id INTO v_new_id;

    IF v_status = c_validado THEN
      change_status(p_complaint_id, c_en_investigacion, p_assigned_by_cip,
                    'Asignacion de investigador titular CIP ' || p_officer_cip);
    END IF;

    RETURN v_new_id;
  EXCEPTION WHEN OTHERS THEN
    ROLLBACK TO sp_assign;
    RAISE;
  END assign_investigator;

  PROCEDURE close_assignment(p_assignment_id IN NUMBER, p_reason IN VARCHAR2) IS
  BEGIN
    UPDATE TB_INV_ASSIGNMENT
       SET end_date = SYSDATE,
           reassignment_reason = SUBSTR(TRIM(p_reason), 1, 200)
     WHERE assignment_id = p_assignment_id AND end_date IS NULL;
    IF SQL%ROWCOUNT = 0 THEN
      RAISE_APPLICATION_ERROR(c_err_not_found, 'Asignacion inexistente o ya cerrada: ' || p_assignment_id);
    END IF;
  END close_assignment;

  PROCEDURE update_assignment_reason(p_assignment_id IN NUMBER, p_reason IN VARCHAR2) IS
  BEGIN
    UPDATE TB_INV_ASSIGNMENT
       SET reassignment_reason = SUBSTR(TRIM(p_reason), 1, 200)
     WHERE assignment_id = p_assignment_id;
    IF SQL%ROWCOUNT = 0 THEN
      RAISE_APPLICATION_ERROR(c_err_not_found, 'Asignacion inexistente: ' || p_assignment_id);
    END IF;
  END update_assignment_reason;

  PROCEDURE delete_assignment(p_assignment_id IN NUMBER) IS
    v_end DATE;
  BEGIN
    BEGIN
      SELECT end_date INTO v_end FROM TB_INV_ASSIGNMENT WHERE assignment_id = p_assignment_id;
    EXCEPTION WHEN NO_DATA_FOUND THEN
      RAISE_APPLICATION_ERROR(c_err_not_found, 'Asignacion inexistente: ' || p_assignment_id);
    END;
    IF v_end IS NULL THEN
      RAISE_APPLICATION_ERROR(c_err_active_assign,
        'No se elimina una asignacion activa; cierrela primero con close_assignment.');
    END IF;
    DELETE FROM TB_INV_ASSIGNMENT WHERE assignment_id = p_assignment_id;
  END delete_assignment;

  FUNCTION get_assignments(p_complaint_id IN NUMBER) RETURN SYS_REFCURSOR IS
    v_rc SYS_REFCURSOR;
  BEGIN
    OPEN v_rc FOR
      SELECT assignment_id, complaint_id, officer_cip, assigned_by_cip,
             assignment_date, end_date, reassignment_reason
        FROM TB_INV_ASSIGNMENT
       WHERE complaint_id = p_complaint_id
       ORDER BY assignment_date;
    RETURN v_rc;
  END get_assignments;

  -- Resincroniza el contador (util tras cargas masivas o correcciones)
  PROCEDURE recalc_active_case_count IS
  BEGIN
    UPDATE TB_STAFF_OFFICER o
       SET active_case_count = (SELECT COUNT(*) FROM TB_INV_ASSIGNMENT a
                                 WHERE a.officer_cip = o.officer_cip AND a.end_date IS NULL);
  END recalc_active_case_count;

  ---------------------------------------------------------- equipo de apoyo
  PROCEDURE add_support_member(p_complaint_id IN NUMBER, p_officer_cip IN VARCHAR2) IS
    v_titular VARCHAR2(15);
  BEGIN
    assert_officer_exists(p_officer_cip);
    BEGIN
      SELECT officer_cip INTO v_titular
        FROM TB_INV_ASSIGNMENT
       WHERE complaint_id = p_complaint_id AND end_date IS NULL;
      IF v_titular = p_officer_cip THEN
        RAISE_APPLICATION_ERROR(c_err_same_officer, 'El titular del caso no puede ser parte del equipo de apoyo.');
      END IF;
    EXCEPTION WHEN NO_DATA_FOUND THEN NULL;
    END;
    INSERT INTO TB_INV_SUPPORT_TEAM (complaint_id, officer_cip) VALUES (p_complaint_id, p_officer_cip);
  END add_support_member;

  PROCEDURE remove_support_member(p_complaint_id IN NUMBER, p_officer_cip IN VARCHAR2) IS
  BEGIN
    DELETE FROM TB_INV_SUPPORT_TEAM
     WHERE complaint_id = p_complaint_id AND officer_cip = p_officer_cip;
    IF SQL%ROWCOUNT = 0 THEN
      RAISE_APPLICATION_ERROR(c_err_not_found, 'El efectivo no pertenece al equipo de apoyo.');
    END IF;
  END remove_support_member;

  FUNCTION get_support_team(p_complaint_id IN NUMBER) RETURN SYS_REFCURSOR IS
    v_rc SYS_REFCURSOR;
  BEGIN
    OPEN v_rc FOR
      SELECT complaint_id, officer_cip FROM TB_INV_SUPPORT_TEAM
       WHERE complaint_id = p_complaint_id ORDER BY officer_cip;
    RETURN v_rc;
  END get_support_team;

  ------------------------------------------------------------- historial
  FUNCTION get_status_history(p_complaint_id IN NUMBER) RETURN SYS_REFCURSOR IS
    v_rc SYS_REFCURSOR;
  BEGIN
    OPEN v_rc FOR
      SELECT history_id, complaint_id, officer_cip, previous_status, new_status,
             change_reason, change_timestamp
        FROM TB_INV_STATUS_HISTORY
       WHERE complaint_id = p_complaint_id
       ORDER BY change_timestamp, history_id;
    RETURN v_rc;
  END get_status_history;

  -------------------------------------------------------------- operativos
  FUNCTION create_operation(p_sector_id IN NUMBER, p_operation_type IN VARCHAR2,
                            p_operation_date IN TIMESTAMP) RETURN NUMBER IS
    v_id NUMBER;
  BEGIN
    INSERT INTO TB_OPS_OPERATION (sector_id, operation_type, operation_date)
    VALUES (p_sector_id, p_operation_type, p_operation_date)
    RETURNING operation_id INTO v_id;
    RETURN v_id;
  END create_operation;

  PROCEDURE update_operation(p_operation_id IN NUMBER, p_sector_id IN NUMBER,
                             p_operation_type IN VARCHAR2, p_operation_date IN TIMESTAMP) IS
  BEGIN
    UPDATE TB_OPS_OPERATION
       SET sector_id = p_sector_id, operation_type = p_operation_type, operation_date = p_operation_date
     WHERE operation_id = p_operation_id;
    IF SQL%ROWCOUNT = 0 THEN
      RAISE_APPLICATION_ERROR(c_err_not_found, 'Operativo inexistente: ' || p_operation_id);
    END IF;
  END update_operation;

  PROCEDURE delete_operation(p_operation_id IN NUMBER) IS
  BEGIN
    DELETE FROM TB_OPS_OPERATION WHERE operation_id = p_operation_id;   -- CASCADE a las asociativas
    IF SQL%ROWCOUNT = 0 THEN
      RAISE_APPLICATION_ERROR(c_err_not_found, 'Operativo inexistente: ' || p_operation_id);
    END IF;
  END delete_operation;

  PROCEDURE link_complaint(p_operation_id IN NUMBER, p_complaint_id IN NUMBER) IS
  BEGIN
    INSERT INTO TB_OPS_OPERATION_COMPLAINT (operation_id, complaint_id)
    VALUES (p_operation_id, p_complaint_id);
  END link_complaint;

  PROCEDURE unlink_complaint(p_operation_id IN NUMBER, p_complaint_id IN NUMBER) IS
  BEGIN
    DELETE FROM TB_OPS_OPERATION_COMPLAINT
     WHERE operation_id = p_operation_id AND complaint_id = p_complaint_id;
    IF SQL%ROWCOUNT = 0 THEN
      RAISE_APPLICATION_ERROR(c_err_not_found, 'La denuncia no esta vinculada al operativo.');
    END IF;
  END unlink_complaint;

  PROCEDURE add_operation_staff(p_operation_id IN NUMBER, p_officer_cip IN VARCHAR2) IS
  BEGIN
    INSERT INTO TB_OPS_OPERATION_STAFF (operation_id, officer_cip)
    VALUES (p_operation_id, p_officer_cip);
  END add_operation_staff;

  PROCEDURE remove_operation_staff(p_operation_id IN NUMBER, p_officer_cip IN VARCHAR2) IS
  BEGIN
    DELETE FROM TB_OPS_OPERATION_STAFF
     WHERE operation_id = p_operation_id AND officer_cip = p_officer_cip;
    IF SQL%ROWCOUNT = 0 THEN
      RAISE_APPLICATION_ERROR(c_err_not_found, 'El efectivo no participa en el operativo.');
    END IF;
  END remove_operation_staff;

  FUNCTION get_operation(p_operation_id IN NUMBER) RETURN SYS_REFCURSOR IS
    v_rc SYS_REFCURSOR;
  BEGIN
    OPEN v_rc FOR
      SELECT o.operation_id, o.sector_id, o.operation_type, o.operation_date,
             (SELECT COUNT(*) FROM TB_OPS_OPERATION_COMPLAINT c WHERE c.operation_id = o.operation_id) AS n_complaints,
             (SELECT COUNT(*) FROM TB_OPS_OPERATION_STAFF s     WHERE s.operation_id = o.operation_id) AS n_staff
        FROM TB_OPS_OPERATION o
       WHERE o.operation_id = p_operation_id;
    RETURN v_rc;
  END get_operation;

  FUNCTION register_operation(p_sector_id      IN NUMBER,
                              p_operation_type IN VARCHAR2,
                              p_operation_date IN TIMESTAMP,
                              p_complaints     IN t_id_list,
                              p_staff          IN t_cip_list) RETURN NUMBER IS
    v_op     NUMBER;
    v_status TB_CPL_COMPLAINT.current_status%TYPE;
    v_sector TB_CPL_COMPLAINT.sector_id%TYPE;
  BEGIN
    SAVEPOINT sp_register_op;

    IF p_complaints IS NULL OR p_complaints.COUNT = 0 THEN
      RAISE_APPLICATION_ERROR(c_err_operation, 'El operativo debe vincular al menos una denuncia.');
    END IF;
    IF p_staff IS NULL OR p_staff.COUNT = 0 THEN
      RAISE_APPLICATION_ERROR(c_err_operation, 'El operativo debe tener al menos un efectivo.');
    END IF;

    FOR i IN 1 .. p_complaints.COUNT LOOP
      BEGIN
        SELECT current_status, sector_id INTO v_status, v_sector
          FROM TB_CPL_COMPLAINT WHERE complaint_id = p_complaints(i);
      EXCEPTION WHEN NO_DATA_FOUND THEN
        RAISE_APPLICATION_ERROR(c_err_not_found, 'Denuncia inexistente: ' || p_complaints(i));
      END;
      IF v_status <> c_intervencion THEN
        RAISE_APPLICATION_ERROR(c_err_operation,
          'La denuncia ' || p_complaints(i) || ' debe estar en INTERVENCION_PROGRAMADA (actual: ' || v_status || ').');
      END IF;
      IF v_sector <> p_sector_id THEN
        RAISE_APPLICATION_ERROR(c_err_operation,
          'La denuncia ' || p_complaints(i) || ' pertenece a otro sector.');
      END IF;
    END LOOP;

    v_op := create_operation(p_sector_id, p_operation_type, p_operation_date);

    FOR i IN 1 .. p_complaints.COUNT LOOP
      link_complaint(v_op, p_complaints(i));
    END LOOP;
    FOR i IN 1 .. p_staff.COUNT LOOP
      assert_officer_exists(p_staff(i));
      add_operation_staff(v_op, p_staff(i));
    END LOOP;

    RETURN v_op;
  EXCEPTION WHEN OTHERS THEN
    ROLLBACK TO sp_register_op;
    RAISE;
  END register_operation;

END PKG_INV_MGMT;
/
SHOW ERRORS PACKAGE PKG_INV_MGMT
SHOW ERRORS PACKAGE BODY PKG_INV_MGMT
