-- Earned rewards consume no points; direct customer inserts remain blocked by existing RLS.
alter table public.reward_redemptions drop constraint if exists reward_redemptions_points_spent_check;
alter table public.reward_redemptions add constraint reward_redemptions_points_spent_check check (points_spent >= 0);
