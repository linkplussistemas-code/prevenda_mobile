import sqlite3

# Abra o mesmo banco de dados que o LinkPlusMotorApp.exe utiliza
conn = sqlite3.connect('database.db')  # <-- Ajuste o nome do arquivo .db se for diferente
cursor = conn.cursor()

# 1. Cria a tabela de celulares permitidos caso não exista
cursor.execute('''
    CREATE TABLE IF NOT EXISTS dispositivos_autorizados (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        numero_celular TEXT UNIQUE NOT NULL
    )
''')

# 2. Insira o seu número de celular (digite EXATAMENTE como vai digitar no app)
# Exemplo: 11999998888 ou 11988887777
meu_celular = "11976334086"  # <-- ALTERE PARA O SEU NÚMERO AQUI

try:
    cursor.execute("INSERT INTO dispositivos_autorizados (numero_celular) VALUES (?)", (meu_celular,))
    conn.commit()
    print(f"✅ Celular {meu_celular} cadastrado com sucesso!")
except sqlite3.IntegrityError:
    print(f"⚠️ O celular {meu_celular} já estava cadastrado.")

conn.close()