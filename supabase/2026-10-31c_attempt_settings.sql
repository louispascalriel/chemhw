-- ChemHW migration — 2026-10-31 (c): per-class settings (attempt limits for ICE / HW)
-- Run once in Supabase: SQL Editor → + → New snippet → paste → Run. Safe to re-run.

alter table public.class_content
  add column if not exists settings jsonb not null default '{}'::jsonb;

-- Tell the API about the new column right away.
notify pgrst, 'reload schema';

select 'OK: settings column ready' as status;
