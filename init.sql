-- Useful extensions
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- Roles
CREATE ROLE web_anon NOLOGIN;

-- =========================
-- BASE TABLES
-- =========================

-- Medical centers (hospitals, clinics, etc.)
CREATE TABLE medical_centers (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    address TEXT NOT NULL,
    phone TEXT,
    email TEXT,
    description TEXT,
    type TEXT CHECK (type IN ('hospital', 'clinic', 'specialized_center', 'laboratory')),
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
    birth_date DATE,
    gender TEXT CHECK (gender IN ('M', 'F', 'Other')),
    address TEXT,
    phone TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Doctors (profile data linked to users)
CREATE TABLE doctors (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID UNIQUE REFERENCES users(id) ON DELETE CASCADE,
    medical_center_id UUID REFERENCES medical_centers(id) ON DELETE SET NULL,
    first_name TEXT NOT NULL,
    last_name TEXT NOT NULL,
    license_number TEXT NOT NULL UNIQUE,
    email TEXT NOT NULL,
    phone TEXT,
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

-- View for appointments with doctor and patient info
CREATE VIEW api.appointments_detailed AS
SELECT 
    a.*,
    p.first_name as patient_first_name,
    p.last_name as patient_last_name,
    p.phone as patient_phone,
    d.first_name as doctor_first_name,
    d.last_name as doctor_last_name,
    d.phone as doctor_phone,
    ms.name as service_name,
    mp.name as procedure_name
FROM appointments a
LEFT JOIN patients p ON a.patient_id = p.id
LEFT JOIN doctors d ON a.doctor_id = d.id
LEFT JOIN medical_services ms ON a.service_id = ms.id
LEFT JOIN medical_procedures mp ON a.procedure_id = mp.id;

-- View for doctor schedules with service info
CREATE VIEW api.doctor_schedules AS
SELECT 
    d.id as doctor_id,
    d.first_name,
    d.last_name,
    d.email,
    d.phone,
    d.medical_center_id,
    mc.name as center_name,
    mc.address as center_address,
    da.day_of_week,
    da.start_time,
    da.end_time,
    ms.name as service_name,
    ms.description as service_description
FROM doctors d
LEFT JOIN medical_centers mc ON d.medical_center_id = mc.id
LEFT JOIN doctor_availability da ON d.id = da.doctor_id
LEFT JOIN doctor_service ds ON d.id = ds.doctor_id
LEFT JOIN medical_services ms ON ds.service_id = ms.id;

-- View for medical centers with services and procedures
CREATE VIEW api.center_services AS
SELECT 
    mc.id as center_id,
    mc.name as center_name,
    mc.address,
    mc.phone,
    mc.email,
    mc.type,
    ms.id as service_id,
    ms.name as service_name,
    ms.description as service_description,
    mp.id as procedure_id,
    mp.name as procedure_name,
    mp.description as procedure_description
FROM medical_centers mc
LEFT JOIN center_service cs ON mc.id = cs.medical_center_id
LEFT JOIN medical_services ms ON cs.service_id = ms.id
LEFT JOIN center_procedure cp ON mc.id = cp.medical_center_id
LEFT JOIN medical_procedures mp ON cp.procedure_id = mp.id;

GRANT SELECT ON api.appointments_detailed TO web_anon;
GRANT SELECT ON api.doctor_schedules TO web_anon;
GRANT SELECT ON api.center_services TO web_anon;