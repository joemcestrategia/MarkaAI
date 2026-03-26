import psycopg2

try:
    conn = psycopg2.connect("postgresql://postgres:postgres@127.0.0.1:54322/postgres")
    cur = conn.cursor()
    cur.execute("""
        SELECT column_name
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'appointments';
    """)
    columns = cur.fetchall()
    print("Columns in 'appointments':")
    for col in columns:
        print(f" - {col[0]}")
    cur.close()
    conn.close()
except Exception as e:
    print(f"Error: {e}")
