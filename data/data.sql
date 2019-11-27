CREATE DATABASE realworld;

\c realworld

CREATE SCHEMA realworld_public;
CREATE SCHEMA realworld_private;

create extension if not exists "pgcrypto";

create table realworld_public.user (
  id uuid primary key default gen_random_uuid(),
  email     text not null check (char_length(email) < 80),
  username  text check (char_length(username) < 80),
  bio       text,
  image     text,
  token     text,
  created_at timestamp default now(),
  updated_at timestamp default now(),
  deleted_at timestamp default now()
);



comment on table realworld_public.user is 'A user of the forum.';
comment on column realworld_public.user.id is 'The primary unique identifier for the user.';
comment on column realworld_public.user.email is 'The email address of the user.';
comment on column realworld_public.user.username is 'The username of the user.';
comment on column realworld_public.user.bio is 'A short description about the user, written by the user.';
comment on column realworld_public.user.image is 'The url where the image is located.';
comment on column realworld_public.user.token is 'The JSON Web Token.';
comment on column realworld_public.user.created_at is 'The time this user was created.';
comment on column realworld_public.user.updated_at is 'The time this user was updated.';
comment on column realworld_public.user.deleted_at is 'The time this user was deleted.';


create function realworld_private.set_updated_at() returns trigger as $$
begin
  new.updated_at := current_timestamp;
  return new;
end;
$$ language plpgsql;

create trigger user_updated_at before update
  on realworld_public.user
  for each row
  execute procedure realworld_private.set_updated_at();

-- create trigger post_updated_at before update
--   on realworld_public.post
--   for each row
--   execute procedure realworld_private.set_updated_at();

-- AUTHENTICATION
create table realworld_private.user_account (
  user_id        uuid primary key references realworld_public.user(id) on delete cascade,
  email            text not null unique check (email ~* '^.+@.+\..+$'),
  password_hash    text not null
);

comment on table realworld_private.user_account is 'Private information about a user account.';
comment on column realworld_private.user_account.user_id is 'The id of the user associated with this account.';
comment on column realworld_private.user_account.email is 'The email address of the user.';
comment on column realworld_private.user_account.password_hash is 'An opaque hash of the user password.';

create extension if not exists "pgcrypto";


create function realworld_public.register_user(
  username text,
  email text,
  password text
) returns realworld_public.user as $$
declare
  user realworld_public.user;
begin
  insert into realworld_public.user (username) values
    (username)
    returning * into user;

  insert into realworld_private.user_account (user_id, email, password_hash) values
    (user_id, email, crypt(password, gen_salt('bf')));

  return user;
end;
$$ language plpgsql strict security definer;

comment on function realworld_public.register_user(text, text, text) is 'Registers a single user and creates an account in our forum.';

-- CREATE ROLES
create role realworld_postgraphile login password 'xyz';

create role realworld_anonymous;
grant realworld_anonymous to realworld_postgraphile;

create role realworld_user;
grant realworld_user to realworld_postgraphile;


-- CREATE JWT TOKEN TYPE
create type realworld_public.jwt_token as (
  role text,
  user_id uuid,
  exp bigint
);


-- CREATE AUTHENTICATION
create function realworld_public.authenticate(
  email text,
  password text
) returns realworld_public.jwt_token as $$
declare
  account realworld_private.user_account;
begin
  select a.* into account
  from realworld_private.user_account as a
  where a.email = $1;
 
  if account.password_hash = crypt(password, account.password_hash) then
    return ('realworld_user', account.user_id, extract(epoch from (now() + interval '2 days')))::realworld.jwt_token;
  else
    return null;
  end if;
end;
$$ language plpgsql strict security definer;

comment on function realworld_public.authenticate(text, text) is 'Creates a JWT token that will securely identify a person and give them certain permissions. This token expires in 2 days.';


-- Function for getting Authorized user
create function realworld_public.current_user() returns realworld_public.user as $$
  select *
  from realworld_public.user
  where id = nullif(current_setting('jwt.claims.person_id', true), '')::uuid
$$ language sql stable;

comment on function realworld_public.current_user() is 'Gets the person who was identified by our JWT.';

-- after schema creation and before function creation
alter default privileges revoke execute on functions from public;

grant usage on schema realworld_public to realworld_anonymous, realworld_user;

grant select on table realworld_public.user to realworld_anonymous, realworld_user;
grant update, delete on table realworld_public.user to realworld_user;

-- grant select on table realworld_public.post to realworld_anonymous, realworld_user;
-- grant insert, update, delete on table realworld_public.post to realworld_user;
-- grant usage on sequence realworld_public.post_id_seq to realworld_user;

-- grant execute on function realworld_public.person_full_name(realworld_public.person) to realworld_anonymous, realworld_user;
-- grant execute on function realworld_public.post_summary(realworld_public.post, integer, text) to realworld_anonymous, realworld_user;
-- grant execute on function realworld_public.person_latest_post(realworld_public.person) to realworld_anonymous, realworld_user;
-- grant execute on function realworld_public.search_posts(text) to realworld_anonymous, realworld_user;
grant execute on function realworld_public.authenticate(text, text) to realworld_anonymous, realworld_user;
grant execute on function realworld_public.current_user() to realworld_anonymous, realworld_user;

grant execute on function realworld_public.register_user(text, text, text) to realworld_anonymous;

-- ENABLE ROW LEVEL SECURITY AND SET POLICIES
alter table realworld.user enable row level security;
-- alter table realworld.user enable row level security;

create policy select_user on realworld_public.user for select
  using (true);

-- create policy select_post on realworld_public.post for select
--   using (true);

create policy update_user on realworld_public.user for update to realworld_user
  using (id = nullif(current_setting('jwt.claims.person_id', true), '')::uuid);

create policy delete_user on realworld_public.user for delete to realworld_user
  using (id = nullif(current_setting('jwt.claims.person_id', true), '')::uuid);

-- create policy insert_post on forum_example.post for insert to forum_example_person
--   with check (author_id = nullif(current_setting('jwt.claims.person_id', true), '')::integer);

-- create policy update_post on forum_example.post for update to forum_example_person
--   using (author_id = nullif(current_setting('jwt.claims.person_id', true), '')::integer);

-- create policy delete_post on forum_example.post for delete to forum_example_person
--   using (author_id = nullif(current_setting('jwt.claims.person_id', true), '')::integer);

--
-- ACCESS via POSTGRAPHILE
-- postgraphile \
  --connection postgres://realworld_postgraphile:xyz@localhost \
  --schema realworld_public \
  --default-role realworld_anonymous \
  --jwt-secret keyboard_kitten \
  --jwt-token-identifier realworld_public.jwt_token