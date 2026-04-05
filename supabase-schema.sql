-- ================================================
-- Panata Database Schema
-- Run this in Supabase SQL Editor
-- ================================================
-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
-- ================================================
-- BUCKETS (top-level life categories)
-- ================================================
CREATE TABLE buckets (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name TEXT NOT NULL UNIQUE,
    description TEXT,
    status TEXT DEFAULT 'active' CHECK (status IN ('active', 'archived')),
    created_at TIMESTAMPTZ DEFAULT NOW()
);
-- ================================================
-- PROJECTS (belong to a bucket)
-- ================================================
CREATE TABLE projects (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    bucket_id UUID NOT NULL REFERENCES buckets(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    description TEXT,
    status TEXT DEFAULT 'active' CHECK (status IN ('active', 'archived', 'completed')),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(bucket_id, name)
);
-- ================================================
-- TASKS (belong to a project)
-- ================================================
CREATE TABLE tasks (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    project_id UUID NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
    task_name TEXT NOT NULL,
    description TEXT,
    deadline TIMESTAMPTZ,
    priority INTEGER DEFAULT 2 CHECK (
        priority BETWEEN 1 AND 4
    ),
    status TEXT DEFAULT 'pending' CHECK (
        status IN (
            'pending',
            'in_progress',
            'completed',
            'cancelled'
        )
    ),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);
-- ================================================
-- TASK_LOGS (activity history for RAG)
-- ================================================
CREATE TABLE task_logs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    task_id UUID NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
    action TEXT NOT NULL,
    summary TEXT,
    logged_at TIMESTAMPTZ DEFAULT NOW()
);
-- ================================================
-- Indexes
-- ================================================
CREATE INDEX idx_projects_bucket ON projects(bucket_id);
CREATE INDEX idx_projects_status ON projects(status);
CREATE INDEX idx_tasks_project ON tasks(project_id);
CREATE INDEX idx_tasks_deadline ON tasks(deadline)
WHERE status = 'pending';
CREATE INDEX idx_tasks_status ON tasks(status);
CREATE INDEX idx_tasks_priority ON tasks(priority)
WHERE status = 'pending';
CREATE INDEX idx_task_logs_task ON task_logs(task_id);
CREATE INDEX idx_task_logs_logged_at ON task_logs(logged_at);
-- ================================================
-- Auto-update trigger
-- ================================================
CREATE OR REPLACE FUNCTION update_updated_at() RETURNS TRIGGER AS $$ BEGIN NEW.updated_at = NOW();
RETURN NEW;
END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER tasks_updated_at BEFORE
UPDATE ON tasks FOR EACH ROW EXECUTE FUNCTION update_updated_at();
-- ================================================
-- SEED: Pre-seed Buckets
-- ================================================
INSERT INTO buckets (name, description)
VALUES (
        'School',
        'University coursework, assignments, and academic tasks'
    ),
    (
        'Personal',
        'Personal life, errands, self-care, and daily tasks'
    ),
    (
        'Side Projects',
        'Hackathons, portfolio projects, learning, and experiments'
    ),
    (
        'Health',
        'Fitness, medical appointments, mental health, and wellness'
    ),
    (
        'Work',
        'Freelance work, internships, and professional tasks'
    ),
    (
        'Finance',
        'Budget tracking, bills, investments, and financial tasks'
    );
-- Create "General" project in each bucket
INSERT INTO projects (bucket_id, name, description)
SELECT id,
    'General',
    'Default project for quick tasks'
FROM buckets;
-- ================================================
-- RPC FUNCTIONS
-- ================================================
-- Get project by name
CREATE OR REPLACE FUNCTION get_project_by_name(p_name TEXT) RETURNS TABLE (
        id UUID,
        name TEXT,
        bucket_id UUID,
        bucket_name TEXT
    ) AS $$ BEGIN RETURN QUERY
SELECT p.id,
    p.name,
    p.bucket_id,
    b.name
FROM projects p
    JOIN buckets b ON b.id = p.bucket_id
WHERE LOWER(p.name) = LOWER(p_name)
    AND p.status = 'active'
LIMIT 1;
END;
$$ LANGUAGE plpgsql;
-- Get project within a specific bucket
CREATE OR REPLACE FUNCTION get_project_in_bucket(p_name TEXT, b_name TEXT) RETURNS TABLE (
        id UUID,
        name TEXT,
        bucket_id UUID,
        bucket_name TEXT
    ) AS $$ BEGIN RETURN QUERY
SELECT p.id,
    p.name,
    p.bucket_id,
    b.name
FROM projects p
    JOIN buckets b ON b.id = p.bucket_id
WHERE LOWER(p.name) = LOWER(p_name)
    AND LOWER(b.name) = LOWER(b_name)
    AND p.status = 'active'
LIMIT 1;
END;
$$ LANGUAGE plpgsql;
-- Get bucket by name
CREATE OR REPLACE FUNCTION get_bucket_by_name(b_name TEXT) RETURNS TABLE (id UUID, name TEXT) AS $$ BEGIN RETURN QUERY
SELECT buckets.id,
    buckets.name
FROM buckets
WHERE LOWER(buckets.name) = LOWER(b_name)
    AND buckets.status = 'active'
LIMIT 1;
END;
$$ LANGUAGE plpgsql;
-- Get "General" project for a bucket
CREATE OR REPLACE FUNCTION get_general_project(b_name TEXT) RETURNS TABLE (
        id UUID,
        name TEXT,
        bucket_id UUID,
        bucket_name TEXT
    ) AS $$ BEGIN RETURN QUERY
SELECT p.id,
    p.name,
    p.bucket_id,
    b.name
FROM projects p
    JOIN buckets b ON b.id = p.bucket_id
WHERE p.name = 'General'
    AND LOWER(b.name) = LOWER(b_name)
    AND p.status = 'active'
LIMIT 1;
END;
$$ LANGUAGE plpgsql;
-- Fuzzy search projects (for disambiguation)
CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE OR REPLACE FUNCTION search_projects(search_term TEXT) RETURNS TABLE (
        id UUID,
        name TEXT,
        bucket_id UUID,
        bucket_name TEXT,
        similarity REAL
    ) AS $$ BEGIN RETURN QUERY
SELECT p.id,
    p.name,
    p.bucket_id,
    b.name,
    similarity(LOWER(p.name), LOWER(search_term)) AS similarity
FROM projects p
    JOIN buckets b ON b.id = p.bucket_id
WHERE p.status = 'active'
    AND (
        LOWER(p.name) LIKE '%' || LOWER(search_term) || '%'
        OR similarity(LOWER(p.name), LOWER(search_term)) > 0.3
    )
ORDER BY similarity DESC
LIMIT 5;
END;
$$ LANGUAGE plpgsql;
-- Get tasks due soon (for daily briefing)
CREATE OR REPLACE FUNCTION get_upcoming_tasks(hours_ahead INTEGER DEFAULT 72) RETURNS TABLE (
        task_id UUID,
        task_name TEXT,
        deadline TIMESTAMPTZ,
        priority INTEGER,
        project_name TEXT,
        bucket_name TEXT
    ) AS $$ BEGIN RETURN QUERY
SELECT t.id,
    t.task_name,
    t.deadline,
    t.priority,
    p.name,
    b.name
FROM tasks t
    JOIN projects p ON p.id = t.project_id
    JOIN buckets b ON b.id = p.bucket_id
WHERE t.status = 'pending'
    AND (
        t.deadline IS NULL
        OR t.deadline <= NOW() + (hours_ahead || ' hours')::INTERVAL
    )
ORDER BY t.priority ASC,
    t.deadline ASC NULLS LAST;
END;
$$ LANGUAGE plpgsql;
-- Create task with automatic logging
CREATE OR REPLACE FUNCTION create_task_with_log(
        p_project_id UUID,
        p_task_name TEXT,
        p_description TEXT DEFAULT NULL,
        p_deadline TIMESTAMPTZ DEFAULT NULL,
        p_priority INTEGER DEFAULT 2
    ) RETURNS UUID AS $$
DECLARE new_task_id UUID;
BEGIN
INSERT INTO tasks (
        project_id,
        task_name,
        description,
        deadline,
        priority
    )
VALUES (
        p_project_id,
        p_task_name,
        p_description,
        p_deadline,
        p_priority
    )
RETURNING id INTO new_task_id;
INSERT INTO task_logs (task_id, action, summary)
VALUES (
        new_task_id,
        'created',
        'Task created: ' || p_task_name
    );
RETURN new_task_id;
END;
$$ LANGUAGE plpgsql;
-- Complete a task
CREATE OR REPLACE FUNCTION complete_task(p_task_id UUID) RETURNS BOOLEAN AS $$ BEGIN
UPDATE tasks
SET status = 'completed'
WHERE id = p_task_id;
INSERT INTO task_logs (task_id, action, summary)
VALUES (
        p_task_id,
        'completed',
        'Task marked as completed'
    );
RETURN TRUE;
END;
$$ LANGUAGE plpgsql;