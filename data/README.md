# CREATE DATABASE and POPULATE DATA

## CREATE DATABASE

Create the postgres database.

```bash
createdb -U postgres realworld
```

## ENVIRONMENT VARIABLES

Create .env files for secrets

```bash
export $PGPW=##### // postgres passowrd
```

## CONNECT TO POSTGRES

Connection format: 'postgres://user:password@domain:port/db?ssl=1'

```bash
psql "postgres://postgres:$PGPW@127.0.0.1:5433/realworld"
```

## CREATE SCHEMAS

```psql
CREATE SCHEMA realworld_public;
CREATE SCHEMA realworld_private;
```

## CREATE USER TABLE

```psql
create extension if not exists "pgcrypto";
```

```psql
create table realworld_public.user (
  id uuid primary key default gen_random_uuid(),
  email     text not null check (char_length(email) < 80),
  username  text check (char_length(username) < 80),
  bio       text,
  image     text,
  token     text,
  created_at timestamp default now()
  updated_at timestamp default now()
  deleted_at timestamp default now()
);

comment on table realworld_public.user is 'A user of the forum.';
comment on column realworld_public.user.id is 'The primary unique identifier for the person.';
comment on column realworld_public.user.email is 'The email address of the user.';
comment on column realworld_public.user.username is 'The username of the user.';
comment on column realworld_public.user.bio is 'A short description about the user, written by the user.';
comment on column realworld_public.user.image is 'The url where the image is located.';
comment on column realworld_public.user.token is 'The JSON Web Token.';
comment on column realworld_public.user.created_at is 'The time this user was created.';
comment on column realworld_public.user.updated_at is 'The time this user was updated.';
comment on column realworld_public.user.deleted_at is 'The time this user was deleted.';

```

## AUTHENITCATION and AUTHORIZATION

```psql
create table realworld_private.user_account (
  user_id        uuid primary key references realworld_public.user(id) on delete cascade,
  email            text not null unique check (email ~* '^.+@.+\..+$'),
  password_hash    text not null
);

comment on table realworld_private.user_account is 'Private information about a person’s account.';
comment on column realworld_private.user_account.user_id is 'The id of the person associated with this account.';
comment on column realworld_private.user_account.email is 'The email address of the person.';
comment on column realworld_private.user_account.password_hash is 'An opaque hash of the person’s password.';
```


## CONNECT TO POSTGRAPHILE
postgraphile -c "postgres://realworld_postgraphile:xyz@127.0.0.1:5433/realworld" --watch --enhance-graphiql -s realworld_public --default-role realworld_anonymous --jwt-secret keyboard_kitten --jwt-token-identifier realworld_public.jwt_token