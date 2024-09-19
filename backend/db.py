import psycopg2
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

        return result

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

    def get_subzone(self, longitude, latitude, number, band):
        subzone_id = 0
        request = """
        SELECT subz.subz_id
        FROM autour.subzones AS subz
        JOIN autour.zones AS z
          ON subz.subz_zone = z.z_id
        WHERE subz.subz_longitude = %s
          AND subz.subz_latitude = %s
          AND z.z_number = %s
          AND z.z_band = %s;
        """

        print("DEBUG: get_subzone")
        result = self.execute_request(request, (longitude, latitude, number, band))
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

    def insert_area_covered(self, subzone_id):
        """
        Add all blank rows for a given subzone.
        """
        request = """
        INSERT INTO area_covered(area_subzone, area_row_in_subzone, area_bitmap)
        VALUES(%s, %s, %s)
        RETURNING area_id;
        """

        print(f"DEBUG: insert_area_covered")
        for row in range(0, 128):
            self.execute_request(request, (subzone_id, row, 0))
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
        area_id,
        area_x
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
            place_area_col_in_subzone,
            last_updated
        )
        VALUES(%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, NOW())
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
            place_area_col_in_subzone = EXCLUDED.place_area_col_in_subzone,
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
            area_id,
            area_x
        ))

        return

    def get_area_bitmap(self, subzone_x, subzone_y, area_y):
        """
        :return: The bitmap of area covered in the given subzone and the
                 corresponding area id.
        """
        area_id = 0
        area_bitmap = 0
        request = """
        SELECT ac.area_id, ac.area_bitmap
        FROM autour.subzones sz
        JOIN autour.area_covered ac ON sz.subz_id = ac.area_subzone
        WHERE sz.subz_longitude = %s
          AND sz.subz_latitude = %s
          AND ac.area_row_in_subzone = %s;
        """
        result = self.execute_request(request, (subzone_x, subzone_y, area_y))
        print(f"DEBUG: get_area_bitmap, {subzone_x}, {subzone_y}, {area_y}")
        print(result)
        if result:
            area_id = result[0][0]
            area_bitmap = result[0][1]

        return area_id, area_bitmap
