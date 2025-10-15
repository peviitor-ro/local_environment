FROM python:3.9-slim

# Setează directorul de lucru
WORKDIR /app

# Copiază fișierele proiectului
COPY requirements.txt .

# Instalează dependențele
RUN pip3 install --no-cache-dir -r requirements.txt

# Copiază restul proiectului
COPY . .

# Expune portul Django (implicit 8000)
EXPOSE 8000

# Comandă de rulare implicită
CMD ["python3", "manage.py", "runserver", "0.0.0.0:8000"]
