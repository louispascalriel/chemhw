-- ChemHW migration — 2026-11-09: attempt limits enforced by the database
-- Run once in Supabase: SQL Editor → + → New snippet → paste → Run. Safe to re-run.
--
-- Before this, attempt limits were only checked in the browser, so a second window (or a
-- crafted request) could get extra tries. This trigger checks every new student answer:
--   • the question must exist and be open (not hidden / Unused / Completed & Closed),
--   • the student must not have solved it already,
--   • the student must have attempts left (limits from class_content.settings, ICE 1 / HW 3 by default).
-- Rejected answers fail with a message starting "CHEMHW:"; the app shows that to the student.
-- Teachers are not limited.

-- The attempt limits live here (also added by 2026-10-31c; repeated so this file works on its own).
alter table public.class_content
  add column if not exists settings jsonb not null default '{}'::jsonb;

create or replace function public.chemhw_check_attempt() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_class   text;
  v_content record;
  v_q       jsonb;
  v_cat     text;
  v_lim     jsonb;
  v_max     int;
  v_prior   int;
  v_solved  boolean;
begin
  if public.is_teacher() then
    return new;
  end if;

  -- One answer at a time per student+question, so two windows can't both slip through.
  perform pg_advisory_xact_lock(hashtext(new.student_id::text || ':' || new.question_id::text));

  select class_code into v_class from profiles where id = new.student_id;
  select questions, settings into v_content from class_content where class_code = v_class;
  if not found then
    return new;   -- no shared content for this class (old setup): nothing to check against
  end if;

  select e into v_q from jsonb_array_elements(v_content.questions) e
    where e->>'id' = new.question_id::text limit 1;
  if v_q is null then
    raise exception 'CHEMHW: question not found';
  end if;
  if coalesce((v_q->>'hidden')::boolean, false) then
    raise exception 'CHEMHW: closed';
  end if;

  select count(*), coalesce(bool_or(correct), false) into v_prior, v_solved
    from student_results where student_id = new.student_id and question_id = new.question_id;
  if v_solved then
    raise exception 'CHEMHW: already solved';
  end if;

  v_cat := coalesce(nullif(v_q->>'category', ''), 'HW');
  v_lim := v_content.settings -> 'attempts' -> v_cat;
  if not coalesce((v_lim->>'unlimited')::boolean, false) then
    v_max := coalesce((v_lim->>'max')::int, case when v_cat = 'ICE' then 1 else 3 end);
    if v_prior >= v_max then
      raise exception 'CHEMHW: no attempts left';
    end if;
  end if;

  new.attempts_used := v_prior + 1;   -- the server's count, not the browser's
  return new;
end;
$$;

revoke all on function public.chemhw_check_attempt() from public;

drop trigger if exists chemhw_check_attempt on public.student_results;
create trigger chemhw_check_attempt
  before insert on public.student_results
  for each row execute function public.chemhw_check_attempt();

notify pgrst, 'reload schema';

select 'OK: attempt limits now enforced by the database' as status;
