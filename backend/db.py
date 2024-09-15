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
            result = cursor.fetchone()
            self.conn.commit()
            cursor.close()
        except (Exception, psycopg2.Error) as error:
            print(f"Error while executing an SQL request")
            print(f"\n\terror: {error}")
            print(f"\n\trequest: {request}")

        return result

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
            return result[0]
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
        INSERT INTO area_covered(area_subzone, area_row_in_subzone)
        VALUES(%s, %s)
        RETURNING area_id;
        """

        print(f"DEBUG: insert_area_covered")
        for row in range(0, 128):
            self.execute_request(request, (subzone_id, row))
        print(f"DEBUG: 128 blank row added for subzone {subzone_id}")

    # TODO
    def insert_place(self):
        return

    # TODO
    def get_area_covered(self, subzone_x, subzone_y, area_x, area_y):
        """
        :return: The bitmap of area covered in in the given subzone.
        """
        return
