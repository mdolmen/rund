import psycopg2
import sys

from psycopg2 import sql

class Database:
    def __init__(self):
        conn_params = {
            'dbname': 'autour',
            'user': 'autour',
            'password': 'mypassword',
            'host': 'localhost',
            'port': '5432'
        }
        
        self.conn = psycopg2.connect(**conn_params)

    def __del__(self):
        self.conn.close()

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

    def get_subzone(self, longitude, latitude):
        subzone_id = 0
        request = """
        SELECT subz.subz_id
        FROM autour.subzones AS subz
        WHERE subz.subz_longitude = %s AND subz.subz_latitude = %s;
        """

        print("DEBUG: get_subzone")
        result = self.execute_request(request, (longitude, latitude))
        print(f"DEBUG: {result}")

        if result:
            return result[0][0]
        else:
            return 0

    def insert_zone(self, number, band):
        zone_id = 0
        request = """
        INSERT INTO zones(z_number, z_band)
        VALUES(%s, %s)
        RETURNING z_id;
        """

        print(f"DEBUG: insert_zone ({number}, {band})")
        result = self.execute_request(request, (number, band))
        print(f"DEBUG: {result}")

        if result:
            zone_id = result[0]

        return zone_id

    def insert_subzone(self, longitude, latitude, zone_id):
        subzone_id = 0
        request = """
        INSERT INTO subzones(subz_longitude, subz_latitude, subz_zone)
        VALUES(%s, %s, %s)
        RETURNING subz_id;
        """

        print(f"DEBUG: insert_subzone")
        result = self.execute_request(request, (longitude, latitude, zone_id))
        print(f"DEBUG: {result}")

        if result:
            subzone_id = result[0]

        return subzone_id

    def insert_area_covered(self, subzone_id, row, col, width, height):
        """
        Add all blank rows for a given subzone.
        """
        request = """
        INSERT INTO area_covered(
            area_subzone,
            area_row,
            area_col,
            area_width,
            area_height,
            area_covered
        )
        VALUES(%s, %s, %s, %s, %s, %s)
        RETURNING area_id;
        """

        print(f"DEBUG: insert_area_covered")
        for row in range(0, 128):
            self.execute_request(request, (subzone_id, row, col, width, height, False))
        print(f"DEBUG: 128 blank row added for subzone {subzone_id}")

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

    def get_places(self, area_id):
        request = """
        SELECT *
        FROM autour.places
        WHERE place_area_id = %s;
        """

        places = []
        result = self.execute_request(request, (area_id,))

        if result:
            places = result

        return places

    def get_area_by_coords(self, row, col):
        area_id = 0
        width = 0
        height = 0
        covered = 0
        request = """
        SELECT area_id, area_width, area_height, area_covered
        FROM autour.area_covered
        WHERE area_row = %s AND area_col = %s;
        """

        result = self.execute_request(request, (row, col))
        print(f"DEBUG: get_area, {row}, {col}")
        print(result)
        if result:
            area_id = result[0][0]
            width = result[0][1]
            height = result[0][2]
            covered = result[0][3]

        return area_id, width, height, covered

    def get_area_by_id(self, area_id):
        subz_id = 0
        row = 0
        col = 0
        width = 0
        height = 0
        covered = 0
        request = """
        SELECT area_subzone, area_row, area_col, area_width, area_height, area_covered
        FROM autour.area_covered
        WHERE area_id = %s;
        """

        result = self.execute_request(request, (area_id,))
        if result:
            subz_id = result[0][0]
            row = result[0][1]
            col = result[0][2]
            width = result[0][3]
            height = result[0][4]
            covered = result[0][5]

        return subz_id, row, col, width, height, covered

    def get_area_id(self, row, col):
        area_id = 0
        request = """
        SELECT area_id
        FROM autour.area_covered
        WHERE area_row = %s AND area_col = %s;
        """

        result = self.execute_request(request, (row, col))
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
