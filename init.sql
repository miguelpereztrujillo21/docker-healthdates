-- Useful extensions
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- Roles
CREATE ROLE web_anon NOLOGIN;

-- =========================
-- BASE TABLES
-- =========================

-- Autonomous communities (Comunidades Autónomas)
CREATE TABLE autonomous_communities (
    id SERIAL PRIMARY KEY,
    name TEXT NOT NULL UNIQUE,
    code TEXT NOT NULL UNIQUE, -- e.g., 'MD', 'CAT', 'AND', etc.
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Provinces (Provincias)
CREATE TABLE provinces (
    id SERIAL PRIMARY KEY,
    name TEXT NOT NULL,
    autonomous_community_id INT REFERENCES autonomous_communities(id) ON DELETE CASCADE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(name, autonomous_community_id)
);

-- Cities/Municipalities (Ciudades/Municipios)
CREATE TABLE cities (
    id SERIAL PRIMARY KEY,
    name TEXT NOT NULL,
    province_id INT REFERENCES provinces(id) ON DELETE CASCADE,
    postal_code TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(name, province_id)
);

-- Medical centers (hospitals, clinics, etc.)
CREATE TABLE medical_centers (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    address TEXT NOT NULL,
    city_id INT REFERENCES cities(id) ON DELETE SET NULL,
    phone TEXT,
    email TEXT,
    website TEXT, -- Sitio web del centro
    description TEXT,
    type TEXT CHECK (type IN ('hospital', 'clinic', 'specialized_center', 'laboratory', 'pharmacy')),
    is_public BOOLEAN DEFAULT true, -- Si es público o privado
    is_active BOOLEAN DEFAULT true,
    capacity INT, -- Número de camas o capacidad
    emergency_services BOOLEAN DEFAULT false, -- Si tiene urgencias 24h
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Users (central authentication and roles)
CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email TEXT UNIQUE NOT NULL,
    hash_password TEXT NOT NULL,
    role TEXT NOT NULL CHECK (role IN ('patient', 'doctor', 'admin', 'center_admin')),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Patients (profile data linked to users)
CREATE TABLE patients (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID UNIQUE REFERENCES users(id) ON DELETE CASCADE,
    first_name TEXT NOT NULL,
    last_name TEXT NOT NULL,
    second_last_name TEXT, -- Segundo apellido (común en España)
    birth_date DATE,
    gender TEXT CHECK (gender IN ('M', 'F', 'Other')),
    address TEXT,
    city_id INT REFERENCES cities(id) ON DELETE SET NULL, -- Ubicación del paciente
    phone TEXT,
    mobile_phone TEXT, -- Teléfono móvil adicional
    emergency_contact_name TEXT, -- Contacto de emergencia
    emergency_contact_phone TEXT,
    national_id TEXT UNIQUE, -- DNI/NIE
    social_security_number TEXT, -- Número de la Seguridad Social
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Doctors (profile data linked to users)
CREATE TABLE doctors (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID UNIQUE REFERENCES users(id) ON DELETE CASCADE,
    medical_center_id UUID REFERENCES medical_centers(id) ON DELETE SET NULL,
    first_name TEXT NOT NULL,
    last_name TEXT NOT NULL,
    second_last_name TEXT, -- Segundo apellido
    license_number TEXT NOT NULL UNIQUE, -- Número de colegiado
    college_name TEXT, -- Colegio profesional (ej: Colegio de Médicos de Madrid)
    email TEXT NOT NULL,
    phone TEXT,
    mobile_phone TEXT,
    specialization_level TEXT CHECK (specialization_level IN ('resident', 'specialist', 'consultant', 'head_of_service')),
    years_experience INT DEFAULT 0,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Medical services (specialties)
CREATE TABLE medical_services (
    id SERIAL PRIMARY KEY,
    name TEXT NOT NULL UNIQUE,
    description TEXT
);

-- Medical procedures (actions performed)
CREATE TABLE medical_procedures (
    id SERIAL PRIMARY KEY,
    name TEXT NOT NULL UNIQUE,
    description TEXT
);

-- Services available at each medical center
CREATE TABLE center_service (
    medical_center_id UUID REFERENCES medical_centers(id) ON DELETE CASCADE,
    service_id INT REFERENCES medical_services(id) ON DELETE CASCADE,
    PRIMARY KEY (medical_center_id, service_id)
);

-- Procedures available at each medical center
CREATE TABLE center_procedure (
    medical_center_id UUID REFERENCES medical_centers(id) ON DELETE CASCADE,
    procedure_id INT REFERENCES medical_procedures(id) ON DELETE CASCADE,
    PRIMARY KEY (medical_center_id, procedure_id)
);

-- Many-to-many association between services and procedures
CREATE TABLE service_procedure (
    service_id INT REFERENCES medical_services(id) ON DELETE CASCADE,
    procedure_id INT REFERENCES medical_procedures(id) ON DELETE CASCADE,
    PRIMARY KEY (service_id, procedure_id)
);

-- Many-to-many association between doctors and services
CREATE TABLE doctor_service (
    doctor_id UUID REFERENCES doctors(id) ON DELETE CASCADE,
    service_id INT REFERENCES medical_services(id) ON DELETE CASCADE,
    PRIMARY KEY (doctor_id, service_id)
);

-- Doctor availability by day and time
CREATE TABLE doctor_availability (
    id SERIAL PRIMARY KEY,
    doctor_id UUID REFERENCES doctors(id) ON DELETE CASCADE,
    day_of_week INT NOT NULL CHECK (day_of_week BETWEEN 0 AND 6), -- 0: Sunday ... 6: Saturday
    start_time TIME NOT NULL,
    end_time TIME NOT NULL,
    UNIQUE (doctor_id, day_of_week, start_time, end_time)
);

-- Appointments
CREATE TABLE appointments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    patient_id UUID REFERENCES patients(id) ON DELETE CASCADE,
    doctor_id UUID REFERENCES doctors(id) ON DELETE CASCADE,
    service_id INT REFERENCES medical_services(id),
    procedure_id INT REFERENCES medical_procedures(id),
    appointment_datetime TIMESTAMP NOT NULL,
    duration_minutes INT DEFAULT 30,
    reason TEXT,
    status TEXT DEFAULT 'pending' CHECK (status IN (
        'pending',           -- Cita programada, esperando confirmación
        'confirmed',         -- Cita confirmada por el paciente
        'in_progress',       -- Cita en curso (paciente en consulta)
        'completed',         -- Cita finalizada exitosamente
        'canceled',          -- Cancelada por el paciente
        'canceled_by_doctor',-- Cancelada por el doctor
        'no_show',           -- Paciente no se presentó
        'rescheduled'        -- Reprogramada
    )),
    notes TEXT,              -- Notas adicionales sobre la cita
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Medical reports linked to appointments
CREATE TABLE medical_reports (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    appointment_id UUID REFERENCES appointments(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    description TEXT,
    file_url TEXT, -- e.g. Supabase, MinIO, S3 link
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Notifications
CREATE TABLE notifications (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(id),
    type TEXT CHECK (type IN ('appointment_reminder', 'appointment_confirmation', 'appointment_cancellation', 'general')),
    title TEXT NOT NULL,
    content TEXT,
    read_at TIMESTAMP,
    sent_at TIMESTAMP,
    status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'sent', 'error')),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Doctor schedule blocks (vacations, special blocks)
CREATE TABLE schedule_blocks (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    doctor_id UUID REFERENCES doctors(id),
    start_datetime TIMESTAMP NOT NULL,
    end_datetime TIMESTAMP NOT NULL,
    reason TEXT,
    type TEXT DEFAULT 'unavailable' CHECK (type IN ('vacation', 'sick_leave', 'meeting', 'unavailable')),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Insurance companies (Compañías de seguros)
CREATE TABLE insurance_companies (
    id SERIAL PRIMARY KEY,
    name TEXT NOT NULL UNIQUE,
    code TEXT UNIQUE, -- Código de la aseguradora
    phone TEXT,
    email TEXT,
    website TEXT,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Patient insurance (Seguros del paciente)
CREATE TABLE patient_insurance (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    patient_id UUID REFERENCES patients(id) ON DELETE CASCADE,
    insurance_company_id INT REFERENCES insurance_companies(id) ON DELETE SET NULL,
    policy_number TEXT NOT NULL,
    is_primary BOOLEAN DEFAULT false, -- Si es el seguro principal
    valid_from DATE,
    valid_to DATE,
    copay_amount DECIMAL(10,2), -- Copago
    coverage_percentage DECIMAL(5,2), -- Porcentaje de cobertura
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(patient_id, insurance_company_id, policy_number)
);

-- Medical history entries (Historial médico)
CREATE TABLE medical_history (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    patient_id UUID REFERENCES patients(id) ON DELETE CASCADE,
    appointment_id UUID REFERENCES appointments(id) ON DELETE SET NULL,
    doctor_id UUID REFERENCES doctors(id) ON DELETE SET NULL,
    entry_type TEXT CHECK (entry_type IN ('diagnosis', 'treatment', 'prescription', 'lab_result', 'procedure', 'note')),
    title TEXT NOT NULL,
    description TEXT,
    diagnosis_code TEXT, -- Código CIE-10
    severity TEXT CHECK (severity IN ('low', 'medium', 'high', 'critical')),
    is_chronic BOOLEAN DEFAULT false,
    entry_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- File attachments for appointments and medical history
CREATE TABLE file_attachments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    entity_type TEXT CHECK (entity_type IN ('appointment', 'medical_history', 'medical_report')),
    entity_id UUID NOT NULL,
    file_name TEXT NOT NULL,
    file_path TEXT NOT NULL,
    file_size BIGINT,
    mime_type TEXT,
    uploaded_by UUID REFERENCES users(id),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Appointment slots (for better scheduling management)
CREATE TABLE appointment_slots (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    doctor_id UUID REFERENCES doctors(id) ON DELETE CASCADE,
    slot_date DATE NOT NULL,
    start_time TIME NOT NULL,
    end_time TIME NOT NULL,
    is_available BOOLEAN DEFAULT true,
    max_appointments INT DEFAULT 1,
    current_appointments INT DEFAULT 0,
    slot_type TEXT DEFAULT 'regular' CHECK (slot_type IN ('regular', 'emergency', 'follow_up')),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(doctor_id, slot_date, start_time)
);

-- Audit log for important changes
CREATE TABLE audit_log (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    table_name TEXT NOT NULL,
    record_id TEXT NOT NULL,
    action TEXT CHECK (action IN ('INSERT', 'UPDATE', 'DELETE')),
    old_values JSONB,
    new_values JSONB,
    changed_by UUID REFERENCES users(id),
    changed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    ip_address INET,
    user_agent TEXT
);

-- System configuration
CREATE TABLE system_config (
    id SERIAL PRIMARY KEY,
    config_key TEXT NOT NULL UNIQUE,
    config_value TEXT,
    description TEXT,
    is_public BOOLEAN DEFAULT false, -- Si la configuración es pública para la API
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- =========================
-- FUNCTIONS FOR TRIGGERS
-- =========================

-- Function to update updated_at timestamp
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ language 'plpgsql';

-- Trigger for appointments updated_at
CREATE TRIGGER update_appointments_updated_at 
    BEFORE UPDATE ON appointments 
    FOR EACH ROW 
    EXECUTE FUNCTION update_updated_at_column();

-- =========================
-- INDEXES FOR PERFORMANCE
-- =========================

CREATE INDEX idx_appointments_doctor ON appointments(doctor_id);
CREATE INDEX idx_appointments_patient ON appointments(patient_id);
CREATE INDEX idx_appointments_datetime ON appointments(appointment_datetime);
CREATE INDEX idx_appointments_status ON appointments(status);
CREATE INDEX idx_doctor_availability_doctor_day ON doctor_availability(doctor_id, day_of_week);
CREATE INDEX idx_notifications_user ON notifications(user_id);
CREATE INDEX idx_notifications_status ON notifications(status);
CREATE INDEX idx_schedule_blocks_doctor ON schedule_blocks(doctor_id);
CREATE INDEX idx_doctors_center ON doctors(medical_center_id);
CREATE INDEX idx_center_service_center ON center_service(medical_center_id);
CREATE INDEX idx_center_procedure_center ON center_procedure(medical_center_id);

-- Geographic indexes
CREATE INDEX idx_provinces_community ON provinces(autonomous_community_id);
CREATE INDEX idx_cities_province ON cities(province_id);
CREATE INDEX idx_medical_centers_city ON medical_centers(city_id);
CREATE INDEX idx_medical_centers_active ON medical_centers(is_active);

-- New table indexes
CREATE INDEX idx_patient_insurance_patient ON patient_insurance(patient_id);
CREATE INDEX idx_patient_insurance_company ON patient_insurance(insurance_company_id);
CREATE INDEX idx_medical_history_patient ON medical_history(patient_id);
CREATE INDEX idx_medical_history_appointment ON medical_history(appointment_id);
CREATE INDEX idx_medical_history_doctor ON medical_history(doctor_id);
CREATE INDEX idx_medical_history_date ON medical_history(entry_date);
CREATE INDEX idx_file_attachments_entity ON file_attachments(entity_type, entity_id);
CREATE INDEX idx_appointment_slots_doctor_date ON appointment_slots(doctor_id, slot_date);
CREATE INDEX idx_appointment_slots_available ON appointment_slots(is_available);
CREATE INDEX idx_audit_log_table_record ON audit_log(table_name, record_id);
CREATE INDEX idx_audit_log_changed_by ON audit_log(changed_by);
CREATE INDEX idx_audit_log_date ON audit_log(changed_at);

-- Performance indexes for patient data
CREATE INDEX idx_patients_national_id ON patients(national_id);
CREATE INDEX idx_patients_city ON patients(city_id);
CREATE INDEX idx_doctors_license ON doctors(license_number);
CREATE INDEX idx_doctors_active ON doctors(is_active);

-- =========================
-- POSTGREST PERMISSIONS
-- =========================
CREATE SCHEMA IF NOT EXISTS api;

GRANT USAGE ON SCHEMA public TO web_anon;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO web_anon;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO web_anon;

-- Function to get current user from JWT
CREATE OR REPLACE FUNCTION api.current_user() RETURNS uuid AS $$
BEGIN
  RETURN current_setting('jwt.claims.user_id', true)::uuid;
END;
$$ LANGUAGE plpgsql STABLE;

-- =========================
-- USEFUL VIEWS FOR API
-- =========================

-- View for medical centers with geographic information
CREATE VIEW api.centers_with_location AS
SELECT 
    mc.id as center_id,
    mc.name as center_name,
    mc.address,
    mc.phone,
    mc.email,
    mc.type,
    mc.description,
    mc.is_active,
    c.name as city_name,
    c.postal_code,
    p.name as province_name,
    ac.name as autonomous_community_name,
    ac.code as autonomous_community_code
FROM medical_centers mc
LEFT JOIN cities c ON mc.city_id = c.id
LEFT JOIN provinces p ON c.province_id = p.id
LEFT JOIN autonomous_communities ac ON p.autonomous_community_id = ac.id
WHERE mc.is_active = true;

-- View for appointments with complete information including location
CREATE VIEW api.appointments_detailed AS
SELECT 
    a.*,
    pt.first_name as patient_first_name,
    pt.last_name as patient_last_name,
    pt.second_last_name as patient_second_last_name,
    CONCAT(pt.first_name, ' ', pt.last_name, 
           CASE WHEN pt.second_last_name IS NOT NULL THEN CONCAT(' ', pt.second_last_name) ELSE '' END) as patient_full_name,
    pt.phone as patient_phone,
    pt.national_id as patient_national_id,
    d.first_name as doctor_first_name,
    d.last_name as doctor_last_name,
    d.second_last_name as doctor_second_last_name,
    CONCAT(d.first_name, ' ', d.last_name, 
           CASE WHEN d.second_last_name IS NOT NULL THEN CONCAT(' ', d.second_last_name) ELSE '' END) as doctor_full_name,
    d.phone as doctor_phone,
    d.license_number,
    ms.name as service_name,
    mp.name as procedure_name,
    mc.name as center_name,
    mc.address as center_address,
    mc.type as center_type,
    c.name as city_name,
    p2.name as province_name,
    ac.name as autonomous_community_name
FROM appointments a
LEFT JOIN patients pt ON a.patient_id = pt.id
LEFT JOIN doctors d ON a.doctor_id = d.id
LEFT JOIN medical_centers mc ON d.medical_center_id = mc.id
LEFT JOIN cities c ON mc.city_id = c.id
LEFT JOIN provinces p2 ON c.province_id = p2.id
LEFT JOIN autonomous_communities ac ON p2.autonomous_community_id = ac.id
LEFT JOIN medical_services ms ON a.service_id = ms.id
LEFT JOIN medical_procedures mp ON a.procedure_id = mp.id;

-- View for doctors with their centers and services (for appointment booking flow)
CREATE VIEW api.doctors_with_services AS
SELECT 
    d.id as doctor_id,
    d.first_name,
    d.last_name,
    d.second_last_name,
    CONCAT(d.first_name, ' ', d.last_name, 
           CASE WHEN d.second_last_name IS NOT NULL THEN CONCAT(' ', d.second_last_name) ELSE '' END) as doctor_full_name,
    d.email,
    d.phone,
    d.license_number,
    d.specialization_level,
    d.years_experience,
    mc.id as center_id,
    mc.name as center_name,
    mc.address as center_address,
    mc.type as center_type,
    mc.is_public as center_is_public,
    c.name as city_name,
    p.name as province_name,
    ac.name as autonomous_community_name,
    ac.code as autonomous_community_code,
    ms.id as service_id,
    ms.name as service_name,
    ms.description as service_description,
    da.day_of_week,
    da.start_time,
    da.end_time
FROM doctors d
INNER JOIN medical_centers mc ON d.medical_center_id = mc.id
LEFT JOIN cities c ON mc.city_id = c.id
LEFT JOIN provinces p ON c.province_id = p.id
LEFT JOIN autonomous_communities ac ON p.autonomous_community_id = ac.id
LEFT JOIN doctor_service ds ON d.id = ds.doctor_id
LEFT JOIN medical_services ms ON ds.service_id = ms.id
LEFT JOIN doctor_availability da ON d.id = da.doctor_id
WHERE mc.is_active = true AND d.is_active = true
ORDER BY ac.name, p.name, c.name, mc.name, d.last_name, d.first_name;

-- View for services available by location (for the booking flow)
CREATE VIEW api.services_by_location AS
SELECT DISTINCT
    ac.id as autonomous_community_id,
    ac.name as autonomous_community_name,
    ac.code as autonomous_community_code,
    p.id as province_id,
    p.name as province_name,
    c.id as city_id,
    c.name as city_name,
    mc.id as center_id,
    mc.name as center_name,
    mc.type as center_type,
    ms.id as service_id,
    ms.name as service_name,
    ms.description as service_description,
    COUNT(d.id) as available_doctors
FROM autonomous_communities ac
JOIN provinces p ON ac.id = p.autonomous_community_id
JOIN cities c ON p.id = c.province_id
JOIN medical_centers mc ON c.id = mc.city_id
JOIN center_service cs ON mc.id = cs.medical_center_id
JOIN medical_services ms ON cs.service_id = ms.id
JOIN doctor_service ds ON ms.id = ds.service_id
JOIN doctors d ON ds.doctor_id = d.id
WHERE mc.is_active = true
GROUP BY ac.id, ac.name, ac.code, p.id, p.name, c.id, c.name, 
         mc.id, mc.name, mc.type, ms.id, ms.name, ms.description
ORDER BY ac.name, p.name, c.name, mc.name, ms.name;

-- View for patient medical history with doctor and center info
CREATE VIEW api.patient_medical_history AS
SELECT 
    mh.*,
    pt.first_name as patient_first_name,
    pt.last_name as patient_last_name,
    pt.second_last_name as patient_second_last_name,
    CONCAT(pt.first_name, ' ', pt.last_name, 
           CASE WHEN pt.second_last_name IS NOT NULL THEN CONCAT(' ', pt.second_last_name) ELSE '' END) as patient_full_name,
    d.first_name as doctor_first_name,
    d.last_name as doctor_last_name,
    d.second_last_name as doctor_second_last_name,
    CONCAT(d.first_name, ' ', d.last_name, 
           CASE WHEN d.second_last_name IS NOT NULL THEN CONCAT(' ', d.second_last_name) ELSE '' END) as doctor_full_name,
    mc.name as center_name,
    a.appointment_datetime
FROM medical_history mh
LEFT JOIN patients pt ON mh.patient_id = pt.id
LEFT JOIN doctors d ON mh.doctor_id = d.id
LEFT JOIN medical_centers mc ON d.medical_center_id = mc.id
LEFT JOIN appointments a ON mh.appointment_id = a.id
ORDER BY mh.entry_date DESC;

-- View for available appointment slots
CREATE VIEW api.available_slots AS
SELECT 
    aps.*,
    d.first_name as doctor_first_name,
    d.last_name as doctor_last_name,
    d.second_last_name as doctor_second_last_name,
    CONCAT(d.first_name, ' ', d.last_name, 
           CASE WHEN d.second_last_name IS NOT NULL THEN CONCAT(' ', d.second_last_name) ELSE '' END) as doctor_full_name,
    mc.name as center_name,
    mc.address as center_address,
    c.name as city_name,
    p.name as province_name
FROM appointment_slots aps
JOIN doctors d ON aps.doctor_id = d.id
JOIN medical_centers mc ON d.medical_center_id = mc.id
LEFT JOIN cities c ON mc.city_id = c.id
LEFT JOIN provinces p ON c.province_id = p.id
WHERE aps.is_available = true 
AND aps.slot_date >= CURRENT_DATE
AND d.is_active = true
AND mc.is_active = true;

-- View for patient insurance information
CREATE VIEW api.patient_insurance_details AS
SELECT 
    pi.*,
    pt.first_name as patient_first_name,
    pt.last_name as patient_last_name,
    pt.second_last_name as patient_second_last_name,
    CONCAT(pt.first_name, ' ', pt.last_name, 
           CASE WHEN pt.second_last_name IS NOT NULL THEN CONCAT(' ', pt.second_last_name) ELSE '' END) as patient_full_name,
    ic.name as insurance_name,
    ic.code as insurance_code
FROM patient_insurance pi
JOIN patients pt ON pi.patient_id = pt.id
JOIN insurance_companies ic ON pi.insurance_company_id = ic.id
WHERE pi.is_active = true;

GRANT SELECT ON api.appointments_detailed TO web_anon;
GRANT SELECT ON api.centers_with_location TO web_anon;
GRANT SELECT ON api.doctors_with_services TO web_anon;
GRANT SELECT ON api.services_by_location TO web_anon;
GRANT SELECT ON api.patient_medical_history TO web_anon;
GRANT SELECT ON api.available_slots TO web_anon;
GRANT SELECT ON api.patient_insurance_details TO web_anon;
GRANT SELECT ON api.patient_medical_history TO web_anon;
GRANT SELECT ON api.available_slots TO web_anon;
GRANT SELECT ON api.patient_insurance_details TO web_anon;

-- =========================
-- SAMPLE DATA
-- =========================

-- Insert Autonomous Communities (main ones)
INSERT INTO autonomous_communities (name, code) VALUES
('Madrid', 'MD'),
('Cataluña', 'CAT'),
('Andalucía', 'AND'),
('Comunidad Valenciana', 'VAL'),
('Galicia', 'GAL'),
('Castilla y León', 'CYL'),
('País Vasco', 'PV'),
('Castilla-La Mancha', 'CLM'),
('Canarias', 'CAN'),
('Murcia', 'MU'),
('Aragón', 'AR'),
('Extremadura', 'EX'),
('Asturias', 'AS'),
('Islas Baleares', 'IB'),
('Navarra', 'NA'),
('Cantabria', 'CB'),
('La Rioja', 'LR');

-- Insert Provinces for Madrid
INSERT INTO provinces (name, autonomous_community_id) VALUES
('Madrid', (SELECT id FROM autonomous_communities WHERE code = 'MD'));

-- Insert Provinces for Cataluña
INSERT INTO provinces (name, autonomous_community_id) VALUES
('Barcelona', (SELECT id FROM autonomous_communities WHERE code = 'CAT')),
('Girona', (SELECT id FROM autonomous_communities WHERE code = 'CAT')),
('Lleida', (SELECT id FROM autonomous_communities WHERE code = 'CAT')),
('Tarragona', (SELECT id FROM autonomous_communities WHERE code = 'CAT'));

-- Insert Provinces for Andalucía
INSERT INTO provinces (name, autonomous_community_id) VALUES
('Sevilla', (SELECT id FROM autonomous_communities WHERE code = 'AND')),
('Málaga', (SELECT id FROM autonomous_communities WHERE code = 'AND')),
('Córdoba', (SELECT id FROM autonomous_communities WHERE code = 'AND')),
('Granada', (SELECT id FROM autonomous_communities WHERE code = 'AND')),
('Cádiz', (SELECT id FROM autonomous_communities WHERE code = 'AND')),
('Jaén', (SELECT id FROM autonomous_communities WHERE code = 'AND')),
('Almería', (SELECT id FROM autonomous_communities WHERE code = 'AND')),
('Huelva', (SELECT id FROM autonomous_communities WHERE code = 'AND'));

-- Insert Cities
INSERT INTO cities (name, province_id, postal_code) VALUES
-- Madrid
('Madrid', (SELECT id FROM provinces WHERE name = 'Madrid'), '28001'),
('Alcalá de Henares', (SELECT id FROM provinces WHERE name = 'Madrid'), '28801'),
('Getafe', (SELECT id FROM provinces WHERE name = 'Madrid'), '28901'),
('Leganés', (SELECT id FROM provinces WHERE name = 'Madrid'), '28911'),

-- Barcelona
('Barcelona', (SELECT id FROM provinces WHERE name = 'Barcelona'), '08001'),
('Hospitalet de Llobregat', (SELECT id FROM provinces WHERE name = 'Barcelona'), '08901'),
('Badalona', (SELECT id FROM provinces WHERE name = 'Barcelona'), '08911'),
('Terrassa', (SELECT id FROM provinces WHERE name = 'Barcelona'), '08221'),

-- Sevilla
('Sevilla', (SELECT id FROM provinces WHERE name = 'Sevilla'), '41001'),
('Dos Hermanas', (SELECT id FROM provinces WHERE name = 'Sevilla'), '41701'),
('Alcalá de Guadaíra', (SELECT id FROM provinces WHERE name = 'Sevilla'), '41500'),

-- Málaga
('Málaga', (SELECT id FROM provinces WHERE name = 'Málaga'), '29001'),
('Marbella', (SELECT id FROM provinces WHERE name = 'Málaga'), '29600'),
('Fuengirola', (SELECT id FROM provinces WHERE name = 'Málaga'), '29640');

-- Insert Medical Services
INSERT INTO medical_services (name, description) VALUES
('Medicina General', 'Atención médica general y consultas preventivas'),
('Cardiología', 'Especialidad médica dedicada al corazón y sistema cardiovascular'),
('Dermatología', 'Especialidad médica dedicada a la piel y sus enfermedades'),
('Traumatología', 'Especialidad médica dedicada al sistema musculoesquelético'),
('Ginecología', 'Especialidad médica dedicada al sistema reproductivo femenino'),
('Pediatría', 'Especialidad médica dedicada a la atención de niños y adolescentes'),
('Oftalmología', 'Especialidad médica dedicada a los ojos y la visión'),
('Otorrinolaringología', 'Especialidad médica dedicada a oído, nariz y garganta'),
('Neurología', 'Especialidad médica dedicada al sistema nervioso'),
('Psiquiatría', 'Especialidad médica dedicada a la salud mental'),
('Endocrinología', 'Especialidad médica dedicada al sistema endocrino'),
('Urología', 'Especialidad médica dedicada al sistema urogenital');

-- Insert Medical Procedures
INSERT INTO medical_procedures (name, description) VALUES
('Consulta médica', 'Consulta médica general'),
('Electrocardiograma', 'Prueba para evaluar la actividad eléctrica del corazón'),
('Ecografía', 'Prueba de imagen por ultrasonidos'),
('Análisis de sangre', 'Extracción y análisis de muestra sanguínea'),
('Radiografía', 'Prueba de imagen por rayos X'),
('Revisión preventiva', 'Chequeo médico preventivo'),
('Biopsia', 'Extracción de muestra de tejido para análisis'),
('Colonoscopia', 'Exploración del colon mediante endoscopia'),
('Mamografía', 'Radiografía especializada de mama'),
('Resonancia magnética', 'Prueba de imagen por resonancia magnética');

-- Insert Medical Centers
INSERT INTO medical_centers (name, address, city_id, phone, email, type, description) VALUES
-- Madrid
('Hospital Universitario La Paz', 'Paseo de la Castellana, 261', 
 (SELECT id FROM cities WHERE name = 'Madrid'), '91 727 70 00', 'info@hulp.es', 'hospital',
 'Hospital universitario de referencia en Madrid'),
 
('Clínica Universidad de Navarra Madrid', 'Calle de Piquer, 1', 
 (SELECT id FROM cities WHERE name = 'Madrid'), '91 353 05 00', 'info@cun.es', 'clinic',
 'Clínica privada de alta especialización'),

('Centro Médico Getafe', 'Calle Real, 45', 
 (SELECT id FROM cities WHERE name = 'Getafe'), '91 696 80 00', 'info@cmgetafe.es', 'clinic',
 'Centro médico privado en Getafe'),

-- Barcelona
('Hospital Clínic de Barcelona', 'Calle Villarroel, 170', 
 (SELECT id FROM cities WHERE name = 'Barcelona'), '93 227 54 00', 'info@clinic.cat', 'hospital',
 'Hospital universitario de referencia en Cataluña'),

('Clínica Quirónsalud Barcelona', 'Plaza Alfonso Comín, 5-7', 
 (SELECT id FROM cities WHERE name = 'Barcelona'), '93 255 40 00', 'info@quironsalud.es', 'clinic',
 'Clínica privada con múltiples especialidades'),

-- Sevilla
('Hospital Universitario Virgen del Rocío', 'Avenida Manuel Siurot, s/n', 
 (SELECT id FROM cities WHERE name = 'Sevilla'), '95 501 20 00', 'info@huvr.es', 'hospital',
 'Complejo hospitalario universitario en Sevilla'),

-- Málaga
('Hospital Regional Universitario de Málaga', 'Avenida de Carlos Haya, s/n', 
 (SELECT id FROM cities WHERE name = 'Málaga'), '95 129 00 00', 'info@hrum.es', 'hospital',
 'Hospital universitario de referencia en la Costa del Sol');

-- Link services to centers (center_service)
-- Hospital La Paz - servicios principales
INSERT INTO center_service (medical_center_id, service_id) 
SELECT mc.id, ms.id 
FROM medical_centers mc, medical_services ms 
WHERE mc.name = 'Hospital Universitario La Paz' 
AND ms.name IN ('Medicina General', 'Cardiología', 'Traumatología', 'Ginecología', 'Pediatría', 'Neurología');

-- Clínica Universidad de Navarra Madrid - servicios especializados
INSERT INTO center_service (medical_center_id, service_id) 
SELECT mc.id, ms.id 
FROM medical_centers mc, medical_services ms 
WHERE mc.name = 'Clínica Universidad de Navarra Madrid' 
AND ms.name IN ('Cardiología', 'Dermatología', 'Oftalmología', 'Endocrinología', 'Urología');

-- Centro Médico Getafe - servicios básicos
INSERT INTO center_service (medical_center_id, service_id) 
SELECT mc.id, ms.id 
FROM medical_centers mc, medical_services ms 
WHERE mc.name = 'Centro Médico Getafe' 
AND ms.name IN ('Medicina General', 'Dermatología', 'Traumatología');

-- Hospital Clínic Barcelona - servicios completos
INSERT INTO center_service (medical_center_id, service_id) 
SELECT mc.id, ms.id 
FROM medical_centers mc, medical_services ms 
WHERE mc.name = 'Hospital Clínic de Barcelona';

-- Quirónsalud Barcelona - servicios privados
INSERT INTO center_service (medical_center_id, service_id) 
SELECT mc.id, ms.id 
FROM medical_centers mc, medical_services ms 
WHERE mc.name = 'Clínica Quirónsalud Barcelona' 
AND ms.name IN ('Medicina General', 'Cardiología', 'Dermatología', 'Ginecología', 'Oftalmología', 'Psiquiatría');

-- Hospital Virgen del Rocío - servicios públicos
INSERT INTO center_service (medical_center_id, service_id) 
SELECT mc.id, ms.id 
FROM medical_centers mc, medical_services ms 
WHERE mc.name = 'Hospital Universitario Virgen del Rocío' 
AND ms.name IN ('Medicina General', 'Cardiología', 'Traumatología', 'Ginecología', 'Pediatría', 'Otorrinolaringología');

-- Hospital Málaga - servicios regionales
INSERT INTO center_service (medical_center_id, service_id) 
SELECT mc.id, ms.id 
FROM medical_centers mc, medical_services ms 
WHERE mc.name = 'Hospital Regional Universitario de Málaga' 
AND ms.name IN ('Medicina General', 'Cardiología', 'Dermatología', 'Traumatología', 'Neurología', 'Urología');

-- Insert sample users
INSERT INTO users (email, hash_password, role) VALUES
('doctor1@hospital.es', crypt('password123', gen_salt('bf')), 'doctor'),
('doctor2@hospital.es', crypt('password123', gen_salt('bf')), 'doctor'),
('doctor3@clinica.es', crypt('password123', gen_salt('bf')), 'doctor'),
('patient1@email.com', crypt('password123', gen_salt('bf')), 'patient'),
('patient2@email.com', crypt('password123', gen_salt('bf')), 'patient'),
('admin@hospital.es', crypt('admin123', gen_salt('bf')), 'admin');

-- Insert sample doctors
INSERT INTO doctors (user_id, medical_center_id, first_name, last_name, second_last_name, license_number, college_name, email, phone, specialization_level, years_experience) VALUES
((SELECT id FROM users WHERE email = 'doctor1@hospital.es'), 
 (SELECT id FROM medical_centers WHERE name = 'Hospital Universitario La Paz'),
 'Ana', 'García', 'López', 'DOC001MAD', 'Colegio de Médicos de Madrid', 'ana.garcia@hulp.es', '91 727 70 01', 'specialist', 8),

((SELECT id FROM users WHERE email = 'doctor2@hospital.es'), 
 (SELECT id FROM medical_centers WHERE name = 'Hospital Clínic de Barcelona'),
 'Carlos', 'Martín', 'Ruiz', 'DOC002BCN', 'Col·legi de Metges de Barcelona', 'carlos.martin@clinic.cat', '93 227 54 01', 'consultant', 12),

((SELECT id FROM users WHERE email = 'doctor3@clinica.es'), 
 (SELECT id FROM medical_centers WHERE name = 'Clínica Universidad de Navarra Madrid'),
 'María', 'Rodríguez', 'Sánchez', 'DOC003MAD', 'Colegio de Médicos de Madrid', 'maria.rodriguez@cun.es', '91 353 05 01', 'specialist', 6);

-- Insert sample patients
INSERT INTO patients (user_id, first_name, last_name, second_last_name, birth_date, gender, address, city_id, phone, mobile_phone, national_id, social_security_number) VALUES
((SELECT id FROM users WHERE email = 'patient1@email.com'), 
 'Juan', 'Pérez', 'González', '1985-03-15', 'M', 'Calle Mayor, 123', 
 (SELECT id FROM cities WHERE name = 'Madrid'), '91 555 1234', '600 111 222', '12345678A', '281234567890'),

((SELECT id FROM users WHERE email = 'patient2@email.com'), 
 'Laura', 'Fernández', 'López', '1990-07-22', 'F', 'Avenida Diagonal, 456', 
 (SELECT id FROM cities WHERE name = 'Barcelona'), '93 555 5678', '600 333 444', '87654321B', '081234567891');

-- Link doctors to services
INSERT INTO doctor_service (doctor_id, service_id) VALUES
-- Dr. Ana García - Cardiología y Medicina General
((SELECT id FROM doctors WHERE email = 'ana.garcia@hulp.es'), 
 (SELECT id FROM medical_services WHERE name = 'Cardiología')),
((SELECT id FROM doctors WHERE email = 'ana.garcia@hulp.es'), 
 (SELECT id FROM medical_services WHERE name = 'Medicina General')),

-- Dr. Carlos Martín - Traumatología
((SELECT id FROM doctors WHERE email = 'carlos.martin@clinic.cat'), 
 (SELECT id FROM medical_services WHERE name = 'Traumatología')),

-- Dr. María Rodríguez - Dermatología y Endocrinología
((SELECT id FROM doctors WHERE email = 'maria.rodriguez@cun.es'), 
 (SELECT id FROM medical_services WHERE name = 'Dermatología')),
((SELECT id FROM doctors WHERE email = 'maria.rodriguez@cun.es'), 
 (SELECT id FROM medical_services WHERE name = 'Endocrinología'));

-- Insert doctor availability (example schedules)
INSERT INTO doctor_availability (doctor_id, day_of_week, start_time, end_time) VALUES
-- Dr. Ana García - Lunes a Viernes 9:00-17:00
((SELECT id FROM doctors WHERE email = 'ana.garcia@hulp.es'), 1, '09:00', '17:00'),
((SELECT id FROM doctors WHERE email = 'ana.garcia@hulp.es'), 2, '09:00', '17:00'),
((SELECT id FROM doctors WHERE email = 'ana.garcia@hulp.es'), 3, '09:00', '17:00'),
((SELECT id FROM doctors WHERE email = 'ana.garcia@hulp.es'), 4, '09:00', '17:00'),
((SELECT id FROM doctors WHERE email = 'ana.garcia@hulp.es'), 5, '09:00', '17:00'),

-- Dr. Carlos Martín - Martes y Jueves 10:00-14:00, Viernes 16:00-20:00
((SELECT id FROM doctors WHERE email = 'carlos.martin@clinic.cat'), 2, '10:00', '14:00'),
((SELECT id FROM doctors WHERE email = 'carlos.martin@clinic.cat'), 4, '10:00', '14:00'),
((SELECT id FROM doctors WHERE email = 'carlos.martin@clinic.cat'), 5, '16:00', '20:00'),

-- Dr. María Rodríguez - Lunes, Miércoles, Viernes 8:00-15:00
((SELECT id FROM doctors WHERE email = 'maria.rodriguez@cun.es'), 1, '08:00', '15:00'),
((SELECT id FROM doctors WHERE email = 'maria.rodriguez@cun.es'), 3, '08:00', '15:00'),
((SELECT id FROM doctors WHERE email = 'maria.rodriguez@cun.es'), 5, '08:00', '15:00');

-- Insert some sample appointments
INSERT INTO appointments (patient_id, doctor_id, service_id, appointment_datetime, reason, status) VALUES
((SELECT id FROM patients WHERE first_name = 'Juan'), 
 (SELECT id FROM doctors WHERE email = 'ana.garcia@hulp.es'),
 (SELECT id FROM medical_services WHERE name = 'Cardiología'),
 '2025-07-20 10:00:00', 'Revisión cardiológica anual', 'confirmed'),

((SELECT id FROM patients WHERE first_name = 'Laura'), 
 (SELECT id FROM doctors WHERE email = 'maria.rodriguez@cun.es'),
 (SELECT id FROM medical_services WHERE name = 'Dermatología'),
 '2025-07-22 14:30:00', 'Revisión de lunares', 'pending');

-- Insert sample insurance companies
INSERT INTO insurance_companies (name, code, phone, website) VALUES
('Sanitas', 'SAN', '91 752 00 00', 'https://www.sanitas.es'),
('Adeslas', 'ADE', '90 210 56 56', 'https://www.adeslas.es'),
('Asisa', 'ASI', '90 010 10 10', 'https://www.asisa.es'),
('DKV', 'DKV', '93 492 83 00', 'https://www.dkvseguros.com'),
('Mapfre', 'MAP', '90 250 25 25', 'https://www.mapfre.es'),
('Cigna', 'CIG', '91 537 17 00', 'https://www.cigna.es'),
('Seguridad Social', 'SS', '901 106 570', 'https://www.seg-social.es');

-- Insert system configuration
INSERT INTO system_config (config_key, config_value, description, is_public) VALUES
('appointment_duration_default', '30', 'Duración por defecto de las citas en minutos', true),
('max_advance_booking_days', '90', 'Máximo número de días para reservar cita por adelantado', true),
('cancellation_limit_hours', '24', 'Horas mínimas para cancelar una cita', true),
('emergency_phone', '112', 'Teléfono de emergencias', true),
('system_name', 'HealthDates', 'Nombre del sistema', true),
('system_version', '1.0.0', 'Versión del sistema', false);

-- Insert sample patient insurance
INSERT INTO patient_insurance (patient_id, insurance_company_id, policy_number, is_primary, valid_from, valid_to, copay_amount, coverage_percentage) VALUES
((SELECT id FROM patients WHERE first_name = 'Juan'), 
 (SELECT id FROM insurance_companies WHERE code = 'SAN'), 
 'SAN123456789', true, '2024-01-01', '2025-12-31', 10.00, 80.00),

((SELECT id FROM patients WHERE first_name = 'Laura'), 
 (SELECT id FROM insurance_companies WHERE code = 'ADE'), 
 'ADE987654321', true, '2024-01-01', '2025-12-31', 15.00, 75.00);

-- Insert sample appointment slots for better scheduling
INSERT INTO appointment_slots (doctor_id, slot_date, start_time, end_time, is_available, slot_type) VALUES
-- Dr. Ana García - próximos 7 días
((SELECT id FROM doctors WHERE email = 'ana.garcia@hulp.es'), CURRENT_DATE + 1, '09:00', '09:30', true, 'regular'),
((SELECT id FROM doctors WHERE email = 'ana.garcia@hulp.es'), CURRENT_DATE + 1, '09:30', '10:00', true, 'regular'),
((SELECT id FROM doctors WHERE email = 'ana.garcia@hulp.es'), CURRENT_DATE + 1, '10:00', '10:30', false, 'regular'),
((SELECT id FROM doctors WHERE email = 'ana.garcia@hulp.es'), CURRENT_DATE + 2, '14:00', '14:30', true, 'regular'),
((SELECT id FROM doctors WHERE email = 'ana.garcia@hulp.es'), CURRENT_DATE + 3, '11:00', '11:30', true, 'follow_up'),

-- Dr. Carlos Martín - próximos días
((SELECT id FROM doctors WHERE email = 'carlos.martin@clinic.cat'), CURRENT_DATE + 2, '10:00', '10:30', true, 'regular'),
((SELECT id FROM doctors WHERE email = 'carlos.martin@clinic.cat'), CURRENT_DATE + 4, '16:00', '16:30', true, 'regular'),
((SELECT id FROM doctors WHERE email = 'carlos.martin@clinic.cat'), CURRENT_DATE + 5, '17:00', '17:30', true, 'regular'),

-- Dr. María Rodríguez - próximos días
((SELECT id FROM doctors WHERE email = 'maria.rodriguez@cun.es'), CURRENT_DATE + 1, '08:30', '09:00', true, 'regular'),
((SELECT id FROM doctors WHERE email = 'maria.rodriguez@cun.es'), CURRENT_DATE + 3, '13:00', '13:30', true, 'regular'),
((SELECT id FROM doctors WHERE email = 'maria.rodriguez@cun.es'), CURRENT_DATE + 5, '09:00', '09:30', true, 'regular');