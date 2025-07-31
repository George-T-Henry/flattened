-- Migration: Create profile flattening function
-- This function extracts and flattens data from public_profiles JSONB to flattened_profiles structure

CREATE OR REPLACE FUNCTION flatten_profile_data(profile_json JSONB, source_original_id TEXT)
RETURNS TABLE (
    original_id TEXT,
    full_name TEXT,
    current_title TEXT,
    location TEXT,
    about_me TEXT,
    linkedin TEXT,
    gender TEXT,
    skills TEXT,
    current_company TEXT,
    current_title_from_workexp TEXT,
    past_experience TEXT,
    full_jsonb JSONB
) AS $$
DECLARE
    work_experience JSONB;
    experience_item JSONB;
    current_job JSONB;
    past_jobs TEXT[] := '{}';
    skills_array TEXT[] := '{}';
    temp_text TEXT;
BEGIN
    -- Set basic fields
    original_id := source_original_id;
    full_name := profile_json->>'name';
    current_title := profile_json->>'headline';
    location := profile_json->>'location';
    about_me := profile_json->>'summary';
    linkedin := profile_json->>'linkedin';
    gender := profile_json->>'gender';
    full_jsonb := profile_json;
    
    -- Extract skills (handle both array and string formats)
    IF profile_json ? 'skills' THEN
        IF jsonb_typeof(profile_json->'skills') = 'array' THEN
            SELECT string_agg(value::text, ', ')
            FROM jsonb_array_elements_text(profile_json->'skills')
            INTO skills;
        ELSE
            skills := profile_json->>'skills';
        END IF;
    END IF;
    
    -- Process work experience to find current job and past experience
    work_experience := profile_json->'work_experience';
    IF work_experience IS NOT NULL AND jsonb_typeof(work_experience) = 'array' THEN
        FOR experience_item IN SELECT * FROM jsonb_array_elements(work_experience)
        LOOP
            temp_text := experience_item->>'end_date';
            
            -- Check if this is current position (no end date or "current"/"present")
            IF temp_text IS NULL OR temp_text = '' OR temp_text ~* '(current|present|ongoing)' THEN
                IF current_job IS NULL THEN -- Take first current job found
                    current_job := experience_item;
                    current_company := experience_item->>'company';
                    current_title_from_workexp := experience_item->>'title';
                END IF;
            ELSE
                -- Add to past experience
                temp_text := CONCAT(
                    COALESCE(experience_item->>'title', ''), 
                    ' at ', 
                    COALESCE(experience_item->>'company', ''),
                    CASE 
                        WHEN experience_item->>'start_date' IS NOT NULL THEN 
                            ' (' || experience_item->>'start_date' || ' - ' || experience_item->>'end_date' || ')'
                        ELSE ''
                    END
                );
                past_jobs := array_append(past_jobs, temp_text);
            END IF;
        END LOOP;
        
        -- Convert past jobs array to string
        IF array_length(past_jobs, 1) > 0 THEN
            past_experience := array_to_string(past_jobs, '; ');
        END IF;
    END IF;
    
    -- If no current job found in work experience, use headline/title fields
    IF current_company IS NULL THEN
        current_company := profile_json->>'current_company';
    END IF;
    
    IF current_title_from_workexp IS NULL THEN
        current_title_from_workexp := current_title;
    END IF;
    
    RETURN NEXT;
END;
$$ LANGUAGE plpgsql;