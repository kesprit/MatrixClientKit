-- Valeurs de TEST : bases locales du harnais, jamais exposées hors du réseau compose.
CREATE USER synapse PASSWORD 'synapse';
CREATE DATABASE synapse OWNER synapse ENCODING 'UTF8' LC_COLLATE 'C' LC_CTYPE 'C' TEMPLATE template0;
CREATE USER mas PASSWORD 'mas';
CREATE DATABASE mas OWNER mas;
