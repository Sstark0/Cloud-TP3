CREATE EXTENSION IF NOT EXISTS postgis;

CREATE TABLE IF NOT EXISTS comercio (
    id        bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nombre    text NOT NULL,
    direccion text NOT NULL,
    ubicacion geography(Point, 4326) NOT NULL
);

CREATE TABLE IF NOT EXISTS producto (
    id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    comercio_id bigint NOT NULL REFERENCES comercio (id),
    nombre      text NOT NULL,
    precio      integer NOT NULL CHECK (precio >= 0),
    disponible  boolean NOT NULL DEFAULT true
);

CREATE INDEX IF NOT EXISTS producto_comercio_idx ON producto (comercio_id);
