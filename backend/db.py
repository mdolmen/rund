import psycopg2
import sys

import utm

from psycopg2 import sql
from concurrent.futures import ThreadPoolExecutor

AREA_WIDTH = 1 / utm.SUBZONE_SPLIT_X
AREA_HEIGHT = 1 / utm.SUBZONE_SPLIT_Y

class Database:
    def __init__(self):
        conn_params = {
            'dbname': 'autour',
            'user': 'autour',
            'password': 'mypassword',
            'host': 'postgres',
            'port': '5432'
        }
        
        self.conn = psycopg2.connect(**conn_params)

        # If this random zone does not exists it means that it's the first
        # connection. Create all the zones.
        if self.get_zone_id(31, 'T') == 0:
            self.init_db()

    def __del__(self):
        self.conn.close()

    def init_db(self):
        """
        Create zones, subzones and areas. Requires approximately 8GB.
        """
        print("[+] Initialising database...")

        # Create zones
        with ThreadPoolExecutor(max_workers=8) as executor:
            [executor.submit(self.create_zones_subzones, i) for i in range(1, 60+1)]

    def create_zones_subzones(self, number):
        for band in "CDEFGHJKLMNPQRSTUVWX":
            print(f"    [*] Creating zone {str(number)+band}...")
            zone_id = self.insert_zone(number, band)

    def execute_request(self, request, args):
        result = None

        try:
            cursor = self.conn.cursor()
            cursor.execute(request, args)
            result = cursor.fetchall()
            self.conn.commit()
            cursor.close()
        except (Exception, psycopg2.Error) as error:
            print(f"Error while executing an SQL request")
            print(f"\n\terror: {error}")
            print(f"\n\trequest: {request}")
            sys.exit(1)

        return result

    def execute_request_noresult(self, request, args):
        result = None

        try:
            cursor = self.conn.cursor()
            cursor.execute(request, args)
            self.conn.commit()
            cursor.close()
        except (Exception, psycopg2.Error) as error:
            print(f"Error while executing an SQL request")
            print(f"\n\terror: {error}")
            print(f"\n\trequest: {request}")

    def get_country(self, country_name):
        # A Place in United States has 'USA' as country name in the formatted
        # address field (we have 'United States' in our db for the 'nicename').
        request = """
        SELECT country_id FROM countries
        WHERE country_nicename = %s
          OR country_iso3 = %s
        """
        result = self.execute_request(request, (country_name, country_name))

        if result:
            return result[0][0]
        else:
            return 0


    def get_zone_id(self, zone, band):
        subzone_id = 0
        request = """
        SELECT z_id
        FROM zones
        WHERE z_number = %s AND z_band = %s;
        """

        result = self.execute_request(request, (zone, band))

        if result:
            return result[0][0]
        else:
            return 0

    def get_subzone(self, longitude, latitude):
        subzone_id = 0
        request = """
        SELECT subz.subz_id
        FROM autour.subzones AS subz
        WHERE subz.subz_longitude = %s AND subz.subz_latitude = %s;
        """

        result = self.execute_request(request, (longitude, latitude))

        if result:
            return result[0][0]
        else:
            return 0

    def get_subzone_by_id(self, subzone_id):
        longitude = 0
        latitude = 0
        request = """
        SELECT subz_longitude, subz_latitude
        FROM subzones
        WHERE subz_id = %s;
        """

        result = self.execute_request(request, (subzone_id,))

        if result:
            longitude = result[0][0]
            latitude = result[0][1]

        return longitude, latitude

    def insert_zone(self, number, band):
        zone_id = -1
        request = """
        INSERT INTO zones(z_number, z_band)
        VALUES(%s, %s)
        RETURNING z_id;
        """

        result = self.execute_request(request, (number, band))

        if result:
            zone_id = result[0][0]

        return zone_id

    def insert_subzone(self, longitude, latitude, zone_id):
        subzone_id = -1
        request = """
        INSERT INTO subzones(subz_longitude, subz_latitude, subz_zone)
        VALUES(%s, %s, %s)
        RETURNING subz_id;
        """

        result = self.execute_request(request, (longitude, latitude, zone_id))

        if result:
            subzone_id = result[0][0]

        return subzone_id

    def insert_areas(self, subzone_id):
        """
        Add all blank rows for a given subzone.
        """
        request = """
        INSERT INTO area_covered(
            area_subzone,
            area_x,
            area_y,
            area_covered
        )
        VALUES(%s, %s, %s, %s)
        RETURNING area_id;
        """

        # Prepare the data in a list of tuples
        data = []
        for x in range(0, 64):
            for y in range(0, 128):
                data.append((subzone_id, x, y, False))

        cursor = self.conn.cursor()
        cursor.executemany(request, data)
        self.conn.commit()

    def insert_place(self,
        formatted_address,
        google_maps_uri,
        primary_type,
        display_name,
        longitude,
        latitude,
        current_opening_hours,
        country,
        area_id
    ) -> None:
        request = """
        INSERT INTO places(
            place_formatted_address,
            place_google_maps_uri,
            place_primary_type,
            place_display_name,
            place_longitude,
            place_latitude,
            place_current_opening_hours,
            place_country,
            place_area_id,
            last_updated
        )
        VALUES(%s, %s, %s, %s, %s, %s, %s, %s, %s, NOW())
        ON CONFLICT (place_formatted_address)
        DO
        UPDATE
        SET
            place_formatted_address = EXCLUDED.place_formatted_address,
            place_google_maps_uri = EXCLUDED.place_google_maps_uri,
            place_primary_type = EXCLUDED.place_primary_type,
            place_display_name = EXCLUDED.place_display_name,
            place_longitude = EXCLUDED.place_longitude,
            place_latitude = EXCLUDED.place_latitude,
            place_current_opening_hours = EXCLUDED.place_current_opening_hours,
            place_country = EXCLUDED.place_country,
            place_area_id = EXCLUDED.place_area_id,
            last_updated = NOW()
        WHERE
            EXTRACT(EPOCH FROM (NOW() - places.last_updated)) / 86400 > 7
        RETURNING place_id;
        """

        self.execute_request(request, (
            formatted_address,
            google_maps_uri,
            primary_type,
            display_name,
            longitude,
            latitude,
            current_opening_hours,
            country,
            area_id
        ))

        return

    def get_places(self, area_ids):
        # Prepare WHERE conditions
        conditions = ""
        for area_id in area_ids:
            if conditions != "":
                conditions += " OR "
            conditions += "place_area_id = %s"

        request = f"""
        SELECT json_agg(
            json_build_object(
                'place_id', place_id,
                'place_formatted_address', place_formatted_address,
                'place_google_maps_uri', place_google_maps_uri,
                'place_primary_type', place_primary_type,
                'place_display_name', place_display_name,
                'place_longitude', place_longitude,
                'place_latitude', place_latitude,
                'place_current_opening_hours', place_current_opening_hours,
                'place_country', place_country,
                'place_area_id', place_area_id,
                'last_updated', last_updated
            )
        )
        FROM autour.places
        WHERE {conditions};
        """

        places = []
        result = self.execute_request(request, area_ids)

        if result:
            places = result[0][0]

        return places

    def get_area_by_coords(self, x, y):
        area_id = 0
        covered = 0
        request = """
        SELECT area_id, area_covered
        FROM autour.area_covered
        WHERE area_x = %s AND area_y = %s;
        """

        result = self.execute_request(request, (x, y))
        if result:
            area_id = result[0][0]
            covered = result[0][1]

        return area_id, covered

    def get_area_by_id(self, area_id):
        subz_id = 0
        x = 0
        y = 0
        covered = 0
        request = """
        SELECT area_subzone, area_x, area_y, area_covered
        FROM autour.area_covered
        WHERE area_id = %s;
        """

        result = self.execute_request(request, (area_id,))
        if result:
            subz_id = result[0][0]
            x = result[0][1]
            y = result[0][2]
            covered = result[0][3]

        return subz_id, x, y, covered

    def get_area_id(self, subzone_lon, subzone_lat, x, y):
        area_id = 0
        request = """
        SELECT area_covered.area_id
        FROM autour.area_covered
        JOIN autour.subzones ON area_covered.area_subzone = subzones.subz_id
        WHERE subzones.subz_longitude = %s
        AND subzones.subz_latitude = %s
        AND area_covered.area_x = %s
        AND area_covered.area_y = %s;
        """

        result = self.execute_request(request, (subzone_lon, subzone_lat, x, y))
        if result:
            area_id = result[0][0]

        return area_id

    def get_area_covered(self, area_id):
        covered = False
        request = """
        SELECT area_covered
        FROM autour.area_covered
        WHERE area_id = %s
        """

        result = self.execute_request(request, (area_id,))

        if result:
            covered = result[0][0]

        return covered

    def set_area_covered(self, area_id, covered):
        request = """
        UPDATE autour.area_covered
        SET area_covered = %s
        WHERE area_id = %s;
        """

        self.execute_request_noresult(request, (covered, area_id))
