import sqlite3
import pandas as pd

def get_db_connection(db_path="data/transit_data.db"):
    """Establish a connection to the SQLite transit database."""
    conn = sqlite3.connect(db_path)
    return conn

def execute_query(query, db_path="data/transit_data.db"):
    """Execute a read query and return a pandas DataFrame."""
    conn = get_db_connection(db_path)
    df = pd.read_sql_query(query, conn)
    conn.close()
    return df
