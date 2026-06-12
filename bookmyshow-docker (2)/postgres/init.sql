-- ============================================================
-- BookMyShow Clone - Database Schema & Seed
-- ============================================================

-- Extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ─── Tables ──────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS movies (
    id          SERIAL PRIMARY KEY,
    title       VARCHAR(255)   NOT NULL,
    genre       VARCHAR(100),
    language    VARCHAR(50)    DEFAULT 'English',
    duration    INTEGER        NOT NULL, -- minutes
    rating      DECIMAL(3,1)   DEFAULT 0.0,
    description TEXT,
    poster_url  VARCHAR(500),
    trailer_url VARCHAR(500),
    release_date DATE,
    created_at  TIMESTAMPTZ    DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS theatres (
    id      SERIAL PRIMARY KEY,
    name    VARCHAR(255) NOT NULL,
    city    VARCHAR(100) NOT NULL,
    address TEXT,
    total_screens INTEGER DEFAULT 1,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS screenings (
    id          SERIAL PRIMARY KEY,
    movie_id    INTEGER REFERENCES movies(id)   ON DELETE CASCADE,
    theatre_id  INTEGER REFERENCES theatres(id) ON DELETE CASCADE,
    screen_no   INTEGER        DEFAULT 1,
    show_time   TIMESTAMPTZ    NOT NULL,
    price       DECIMAL(10,2)  NOT NULL,
    total_seats INTEGER        DEFAULT 100,
    available_seats INTEGER    DEFAULT 100,
    created_at  TIMESTAMPTZ    DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS seats (
    id           SERIAL PRIMARY KEY,
    screening_id INTEGER REFERENCES screenings(id) ON DELETE CASCADE,
    row_label    CHAR(1)       NOT NULL,
    seat_number  INTEGER       NOT NULL,
    category     VARCHAR(20)   DEFAULT 'regular', -- regular, premium, recliner
    price        DECIMAL(10,2) NOT NULL,
    is_booked    BOOLEAN       DEFAULT FALSE,
    created_at   TIMESTAMPTZ   DEFAULT NOW(),
    UNIQUE(screening_id, row_label, seat_number)
);

CREATE TABLE IF NOT EXISTS bookings (
    id           SERIAL PRIMARY KEY,
    booking_ref  VARCHAR(50)   UNIQUE NOT NULL,
    screening_id INTEGER REFERENCES screenings(id),
    user_name    VARCHAR(255)  NOT NULL,
    user_email   VARCHAR(255)  NOT NULL,
    seat_ids     INTEGER[]     NOT NULL,
    total_amount DECIMAL(10,2) NOT NULL,
    status       VARCHAR(20)   DEFAULT 'confirmed',
    created_at   TIMESTAMPTZ   DEFAULT NOW()
);

-- ─── Indexes ─────────────────────────────────────────────────

CREATE INDEX idx_screenings_movie    ON screenings(movie_id);
CREATE INDEX idx_screenings_theatre  ON screenings(theatre_id);
CREATE INDEX idx_screenings_showtime ON screenings(show_time);
CREATE INDEX idx_seats_screening     ON seats(screening_id);
CREATE INDEX idx_bookings_ref        ON bookings(booking_ref);
CREATE INDEX idx_bookings_email      ON bookings(user_email);

-- ─── Seed Data ───────────────────────────────────────────────

INSERT INTO movies (title, genre, language, duration, rating, description, poster_url, release_date) VALUES
('Kalki 2898 AD',       'Sci-Fi/Action',  'Telugu',  180, 8.5, 'An epic sci-fi adventure blending mythology with futuristic technology.',         'https://via.placeholder.com/300x450/c0392b/ffffff?text=Kalki+2898+AD',    '2024-06-27'),
('Pushpa 2: The Rule',  'Action/Drama',   'Telugu',  190, 8.3, 'Pushpa Raj continues his rise against the red sandalwood smuggling mafia.',        'https://via.placeholder.com/300x450/e67e22/ffffff?text=Pushpa+2',          '2024-12-05'),
('Devara',              'Action/Thriller','Telugu',  165, 7.8, 'A fearless sea pirate rules the coastline in a tale of power and legacy.',          'https://via.placeholder.com/300x450/2980b9/ffffff?text=Devara',            '2024-09-27'),
('Singham Again',       'Action',         'Hindi',   145, 7.2, 'ACP Bajirao Singham leads a mission to rescue his wife from the villain.',           'https://via.placeholder.com/300x450/27ae60/ffffff?text=Singham+Again',     '2024-11-01'),
('Vettaiyan',           'Action/Drama',   'Tamil',   170, 7.9, 'A veteran cop confronts the justice system in his own unorthodox way.',             'https://via.placeholder.com/300x450/8e44ad/ffffff?text=Vettaiyan',         '2024-10-10'),
('Mufasa: The Lion King','Animation',     'English', 120, 7.5, 'The origin story of Mufasa, the legendary king of the Pride Lands.',               'https://via.placeholder.com/300x450/f39c12/ffffff?text=Mufasa',            '2024-12-20'),
('Deadpool & Wolverine', 'Action/Comedy', 'English', 128, 8.1, 'Wade Wilson teams up with Wolverine in this R-rated Marvel adventure.',             'https://via.placeholder.com/300x450/e74c3c/ffffff?text=Deadpool+Wolverine','2024-07-26'),
('Dune: Part Two',      'Sci-Fi',         'English', 166, 8.7, 'Paul Atreides unites with Chani and the Fremen to wage war on the conspirators.',   'https://via.placeholder.com/300x450/1abc9c/ffffff?text=Dune+Part+Two',    '2024-03-01')
ON CONFLICT DO NOTHING;

INSERT INTO theatres (name, city, address, total_screens) VALUES
('PVR INOX Nexus',        'Coimbatore', 'Nexus Mall, Avinashi Road, Coimbatore - 641014',     5),
('SPI Cinemas Brookefields','Coimbatore','Brookefields Mall, Race Course Road, Coimbatore',   4),
('Sree Bharathi Theatre', 'Coimbatore', 'Cross Cut Road, Gandhipuram, Coimbatore - 641012',   2),
('PVR Phoenix Marketcity','Chennai',    'Phoenix MarketCity, Velachery, Chennai - 600042',    8),
('AGS Cinemas OMR',       'Chennai',    'OMR Road, Perungudi, Chennai - 600096',              6),
('INOX Lulu Mall',        'Bengaluru',  'Lulu Mall, Rajajinagar, Bengaluru - 560010',         7)
ON CONFLICT DO NOTHING;

-- Screenings for next 3 days
DO $$
DECLARE
  m  RECORD;
  t  RECORD;
  d  INTEGER;
  show_times TEXT[] := ARRAY['10:00','13:30','17:00','20:30'];
  st TEXT;
  sid INTEGER;
  r  CHAR(1);
  sn INTEGER;
  cat VARCHAR(20);
  pr DECIMAL;
BEGIN
  FOR m IN SELECT id FROM movies LIMIT 4 LOOP
    FOR t IN SELECT id FROM theatres LOOP
      FOR d IN 0..2 LOOP
        FOREACH st IN ARRAY show_times LOOP
          INSERT INTO screenings (movie_id, theatre_id, screen_no, show_time, price, total_seats, available_seats)
          VALUES (
            m.id, t.id, 1,
            (NOW()::date + d + st::time)::timestamptz,
            CASE st WHEN '20:30' THEN 300 WHEN '17:00' THEN 250 ELSE 180 END,
            120, 120
          )
          RETURNING id INTO sid;

          -- Generate seats A-J, 1-12
          FOR r IN SELECT chr(generate_series(65,74)) LOOP
            FOR sn IN 1..12 LOOP
              cat := CASE WHEN r IN ('A','B') THEN 'recliner'
                          WHEN r IN ('C','D','E') THEN 'premium'
                          ELSE 'regular' END;
              pr := CASE cat
                        WHEN 'recliner' THEN 500
                        WHEN 'premium' THEN 350
                        ELSE 180 END;
              INSERT INTO seats (screening_id, row_label, seat_number, category, price)
              VALUES (sid, r, sn, cat, pr)
              ON CONFLICT DO NOTHING;
            END LOOP;
          END LOOP;

        END LOOP;
      END LOOP;
    END LOOP;
  END LOOP;
END $$;

-- Summary
SELECT 'Movies'    AS entity, COUNT(*) FROM movies
UNION ALL
SELECT 'Theatres',              COUNT(*) FROM theatres
UNION ALL
SELECT 'Screenings',            COUNT(*) FROM screenings
UNION ALL
SELECT 'Seats',                 COUNT(*) FROM seats;
