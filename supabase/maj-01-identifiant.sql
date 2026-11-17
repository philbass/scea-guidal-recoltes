-- =====================================================================
--  Mise à jour n°1 — permettre au responsable de changer un identifiant
--  À coller une fois dans Supabase > SQL Editor > New query > Run
--  (déjà incluse dans schema.sql pour une nouvelle installation)
-- =====================================================================

create or replace function public.changer_identifiant(p_user uuid, p_ident text)
returns void language plpgsql security definer set search_path = public, auth as $$
declare
  v_domaine text;
  v_email   text;
begin
  if coalesce(public.mon_role(), '') <> 'responsable' then
    raise exception 'Réservé au responsable';
  end if;
  p_ident := lower(trim(p_ident));
  if p_ident !~ '^[a-z0-9._-]{2,40}$' then
    raise exception 'Identifiant invalide : lettres minuscules, chiffres, point ou tiret';
  end if;
  select split_part(email, '@', 2) into v_domaine from auth.users where id = p_user;
  if v_domaine is null or v_domaine = '' then
    raise exception 'Compte introuvable';
  end if;
  v_email := p_ident || '@' || v_domaine;
  if exists (select 1 from public.profils where identifiant = p_ident and id <> p_user)
     or exists (select 1 from auth.users where lower(email) = v_email and id <> p_user) then
    raise exception 'Cet identifiant existe déjà';
  end if;
  update auth.users set email = v_email, updated_at = now() where id = p_user;
  update auth.identities
     set identity_data = jsonb_set(identity_data, '{email}', to_jsonb(v_email)), updated_at = now()
   where user_id = p_user and provider = 'email';
  update public.profils set identifiant = p_ident where id = p_user;
end $$;

revoke all on function public.changer_identifiant(uuid, text) from public, anon;
grant execute on function public.changer_identifiant(uuid, text) to authenticated;
