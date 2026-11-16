
// PROYECTO: GEO-DENUNCIA (UNMSM - FISI 2026-II)


// Seleccionar la base de datos en modo script (compatible con .js y Compass)
db = db.getSiblingDB("geo_denuncia_nosql");

// Limpieza preventiva por si se ejecuta más de una vez en la prueba en vivo
db.cpl_digital_evidence.drop();
db.cpl_complaint.drop();
db.ops_operation_complaint.drop();
db.inv_status_history.drop();
db.com_neighborhood_assoc.drop();



// 1. COLECCIÓN: cpl_digital_evidence (Basada en TB_CPL_DIGITAL_EVIDENCE)



db.cpl_digital_evidence.insertMany([
  {
    evidence_id: 1,
    complaint_id: 100005,
    uploaded_by_cip: "10000006",
    evidence_type: "GRABACION DE AUDIO",
    file_path: "/evidencias/2026/audio_100005.opus",
    description_ev: "Llamada extorsiva exigiendo pago semanal",
    upload_date: new Date("2026-11-10T14:20:00Z"),
    technical_metadata: {
      duration_sec: 48,
      codec: "opus",
      sha256: "9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08",
      voice_transcript: "Tienen hasta el viernes para depositar los 500 soles"
    },
    forensic_status: "PENDING"
  },
  {
    evidence_id: 2,
    complaint_id: 100007,
    uploaded_by_cip: "10000008",
    evidence_type: "VIDEO DE SEGURIDAD",
    file_path: "/evidencias/2026/cam_100007.mp4",
    description_ev: "Registro de cámara externa durante atentado en local",
    upload_date: new Date("2026-11-11T09:15:00Z"),
    technical_metadata: {
      resolution: "1920x1080",
      fps: 30,
      camera_code: "CAM-SJL-04"
    },
    forensic_status: "VERIFIED"
  },
  {
    evidence_id: 3,
    complaint_id: 100009,
    uploaded_by_cip: "10000008",
    evidence_type: "SCREENSHOT",
    file_path: "/evidencias/2026/chat_descartado.png",
    description_ev: "Captura ilegible de mensajería",
    upload_date: new Date("2026-11-11T10:00:00Z"),
    forensic_status: "DISCARDED"
  },
  {
    evidence_id: 4,
    complaint_id: 100005,
    uploaded_by_cip: "10000006",
    evidence_type: "FOTO",
    file_path: "/evidencias/2026/foto_fachada_100005.jpg",
    description_ev: "Fotografía tomada en vivo del manuscrito extorsivo dejado en la puerta",
    upload_date: new Date(),
    technical_metadata: {
      format: "JPEG",
      resolution: "4032x3024",
      file_size_kb: 2450,
      sha256: "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
      exif_camera: {
        device: "Samsung Galaxy S24",
        gps_captured: [-76.9850, -11.9650]
      }
    },
    forensic_status: "PENDING"
  }
]);


db.cpl_digital_evidence.find({ forensic_status: "PENDING" });


db.cpl_digital_evidence.updateOne(
  { evidence_id: 1 },
  {
    $set: { forensic_status: "VERIFIED" },
    $push: { tags: "voice_match_confirmed" }
  }
);


db.cpl_digital_evidence.deleteMany({ forensic_status: "DISCARDED" });



// 2. COLECCIÓN: cpl_complaint (Basada en TB_CPL_COMPLAINT)



db.cpl_complaint.insertMany([
  {
    complaint_id: 100005,
    sector_id: 4,
    modality: { modality_id: 2, modality_name: "Extorsion telefonica", severity_level: "HIGH" },
    establishment: {
      establishment_id: 1003,
      establishment_name: "Ferreteria El Sol",
      establishment_type: "COMMERCE"
    },
    incident_date: new Date("2026-11-09T18:30:00Z"),
    registration_date: new Date("2026-11-10T08:00:00Z"),
    is_anonymous: "N",
    id_reporter: 1004,
    currency_code: "PEN",
    amount_original: 500.00,
    amount_pen: 500.00,
    payment_frequency: "SEMANALMENTE",
    extortionist_alias: "Los Malditos de SJL",
    current_status: "EN_INVESTIGACION",
    incident_address: "Av. Proceres de la Independencia 1420",
    incident_location: { type: "Point", coordinates: [-76.9850, -11.9650] }
  },
  {
    complaint_id: 100007,
    sector_id: 3,
    modality: { modality_id: 5, modality_name: "Atentado", severity_level: "CRITICAL" },
    incident_date: new Date("2026-11-10T22:10:00Z"),
    registration_date: new Date("2026-11-11T07:45:00Z"),
    is_anonymous: "Y",
    protected_code: 5012,
    currency_code: "USD",
    amount_original: 1000.00,
    amount_pen: 3750.00,
    payment_frequency: "MENSUALMENTE",
    current_status: "INTERVENCION_PROGRAMADA",
    incident_address: "Jr. Los Jardines Oeste 410",
    incident_location: { type: "Point", coordinates: [-76.9950, -11.9650] }
  }
]);

// Crear índice geoespacial 2dsphere sobre incident_location
db.cpl_complaint.createIndex({ incident_location: "2dsphere" });

// [READ] Buscar denuncias críticas o en estado INTERVENCION_PROGRAMADA
db.cpl_complaint.find({
  current_status: "INTERVENCION_PROGRAMADA",
  "modality.severity_level": "CRITICAL"
});


db.cpl_complaint.updateOne(
  { complaint_id: 100007 },
  { $set: { current_status: "DERIVADO_FISCALIA" } }
);


db.cpl_complaint.deleteMany({ current_status: "TEST_DRAFT" });



// 3. COLECCIÓN: ops_operation_complaint (Basada en TB_OPS_OPERATION_COMPLAINT)



db.ops_operation_complaint.insertMany([
  {
    operation_id: 1,
    complaint_id: 100007,
    sector_id: 3,
    operation_type: "PATRULLAJE FOCALIZADO",
    operation_status: "PROGRAMADO",
    assigned_officer_cip: "10000008",
    field_notes: "Despliegue preventivo en perímetro comercial de San Hilarion Norte",
    tactical_log: [
      { timestamp: new Date("2026-11-11T11:00:00Z"), unit: "PAT-04", note: "Perímetro asegurado sin novedad" }
    ]
  },
  {
    operation_id: 2,
    complaint_id: 100005,
    sector_id: 4,
    operation_type: "OPERATIVO_ENCUBIERTO",
    operation_status: "CANCELADO",
    assigned_officer_cip: "10000006",
    field_notes: "Cancelado por reprogramación de inteligencia"
  }
]);


db.ops_operation_complaint.find({ assigned_officer_cip: "10000008" });


db.ops_operation_complaint.updateOne(
  { operation_id: 1, complaint_id: 100007 },
  {
    $set: { operation_status: "EJECUTADO" },
    $push: {
      tactical_log: {
        timestamp: new Date("2026-11-11T13:30:00Z"),
        unit: "PAT-04",
        note: "Intervención exitosa; se recabaron imágenes de cámaras vecinales"
      }
    }
  }
);


db.ops_operation_complaint.deleteMany({ operation_status: "CANCELADO" });



// 4. COLECCIÓN: inv_status_history (Basada en TB_INV_STATUS_HISTORY)


db.inv_status_history.insertMany([
  {
    history_id: 101,
    complaint_id: 100007,
    officer_cip: "10000003",
    previous_status: "REGISTRADO",
    new_status: "VALIDADO_COMISARIA",
    change_reason: "Validacion inicial por oficial de guardia",
    observations: "Coordenadas verificadas dentro del Sector 03",
    change_timestamp: new Date("2026-11-11T08:00:00Z")
  },
  {
    history_id: 102,
    complaint_id: 100007,
    officer_cip: "10000008",
    previous_status: "VALIDADO_COMISARIA",
    new_status: "EN_INVESTIGACION",
    change_reason: "Asignacion de investigador titular CIP 10000008",
    observations: "Inicio de diligencias preliminares y análisis de video",
    change_timestamp: new Date("2026-11-11T08:15:00Z")
  }
]);


db.inv_status_history.find({ complaint_id: 100007 }).sort({ change_timestamp: 1 });


db.inv_status_history.updateOne(
  { history_id: 102 },
  { $set: { audit_verified_by: "GEO_AUDITOR", audit_checked: true } }
);


db.inv_status_history.deleteMany({ is_temp_audit: true });



// 5. COLECCIÓN: com_neighborhood_assoc (Basada en TB_COM_NEIGHBORHOOD_ASSOC)



db.com_neighborhood_assoc.insertMany([
  {
    assoc_id: 1,
    sector_id: 1,
    assoc_name: "JUNTA VECINAL CANTO REY COMERCIAL",
    coordinator_name: "Mario Lopez Rivas",
    coordinator_phone: "987654001",
    authorized_channel: {
      channel_id: 1,
      channel_type: "WhatsApp",
      channel_contact: "+51 987 000 111"
    },
    is_active_alert_group: true
  },
  {
    assoc_id: 3,
    sector_id: 3,
    assoc_name: "JUNTA VECINAL SAN HILARION NORTE",
    coordinator_name: "Pablo Soto Vera",
    coordinator_phone: "987654003",
    authorized_channel: {
      channel_id: 1,
      channel_type: "WhatsApp",
      channel_contact: "+51 987 000 111"
    },
    is_active_alert_group: true
  },
  {
    assoc_id: 99,
    sector_id: 6,
    assoc_name: "JUNTA VECINAL PILOTO INACTIVA",
    coordinator_name: "Registro Temporal",
    coordinator_phone: "900000000",
    authorized_channel: {
      channel_id: 3,
      channel_type: "Radio",
      channel_contact: "Frecuencia 98.5 FM"
    },
    is_active_alert_group: false
  }
]);


db.com_neighborhood_assoc.find({
  is_active_alert_group: true,
  "authorized_channel.channel_type": "WhatsApp"
});


db.com_neighborhood_assoc.updateOne(
  { assoc_id: 3 },
  { $set: { coordinator_phone: "987654999" } }
);


db.com_neighborhood_assoc.deleteMany({ is_active_alert_group: false });

print("=== RESUMEN DE COLECCIONES EN MONGO DB ===");
print("cpl_digital_evidence     : " + db.cpl_digital_evidence.countDocuments());
print("cpl_complaint            : " + db.cpl_complaint.countDocuments());
print("ops_operation_complaint  : " + db.ops_operation_complaint.countDocuments());
print("inv_status_history       : " + db.inv_status_history.countDocuments());
print("com_neighborhood_assoc   : " + db.com_neighborhood_assoc.countDocuments());