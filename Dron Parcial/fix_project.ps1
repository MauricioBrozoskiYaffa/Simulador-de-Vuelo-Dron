$program = @'
using System;
using System.IO;
using Microsoft.Extensions.Configuration;
using DroneSimulator.Data;
using DroneSimulator.Services;

namespace DroneSimulator
{
    class Program
    {
        static void Main(string[] args)
        {
            Console.WriteLine("SIMULADOR DE TRAYECTORIA DE DRON AUTOMATIZADO\n");

            IConfiguration configuration;
            try
            {
                var builder = new ConfigurationBuilder()
                    .SetBasePath(Directory.GetCurrentDirectory())
                    .AddJsonFile("appsettings.json", optional: false, reloadOnChange: true);

                configuration = builder.Build();
            }
            catch (Exception ex)
            {
                Console.WriteLine($"Error al cargar la configuración: {ex.Message}");
                return;
            }

            string connectionString = configuration.GetConnectionString("PostgresConnection") ?? string.Empty;
            if (string.IsNullOrEmpty(connectionString))
            {
                Console.WriteLine("Error: No se encontró la cadena de conexión en appsettings.json.");
                return;
            }

            var persistencia = new GestorPersistencia(connectionString);
            try
            {
                persistencia.InicializarBaseDeDatos();
            }
            catch (Exception ex)
            {
                Console.WriteLine($"Error al verificar/crear la estructura de datos: {ex.Message}");
                return;
            }

            Console.Write("Ingrese el tamaño del terreno (N x N): ");
            if (!int.TryParse(Console.ReadLine(), out int n) || n < 1)
            {
                Console.WriteLine("Error: El tamaño N debe ser un entero mayor o igual a 1.");
                return;
            }

            Console.Write("Ingrese la coordenada inicial X (Fila): ");
            if (!int.TryParse(Console.ReadLine(), out int startX) || startX < 0 || startX >= n)
            {
                Console.WriteLine($"Error: La coordenada X debe estar entre 0 y {n - 1}.");
                return;
            }

            Console.Write("Ingrese la coordenada inicial Y (Columna): ");
            if (!int.TryParse(Console.ReadLine(), out int startY) || startY < 0 || startY >= n)
            {
                Console.WriteLine($"Error: La coordenada Y debe estar entre 0 y {n - 1}.");
                return;
            }

            Console.WriteLine("\nProcesando simulación de ruta...");

            var simulador = new SimuladorVuelo(n, startX, startY);
            bool exito = simulador.Resolver();

            Console.WriteLine("\nMAPA RESULTANTE DE LA EXPLORACIÓN:");
            int[,] tablero = simulador.Tablero;

            for (int i = 0; i < n; i++)
            {
                for (int j = 0; j < n; j++)
                {
                    if (tablero[i, j] == -1)
                    {
                        Console.Write(".\t");
                    }
                    else
                    {
                        Console.Write($"{tablero[i, j]}\t");
                    }
                }
                Console.WriteLine();
            }

            if (!exito)
            {
                Console.WriteLine("\nSIN SOLUCIÓN: El dron exploró las alternativas pero no halló una ruta completa.");
                return;
            }

            Console.WriteLine("\n¡ÉXITO! El dron cubrió de manera óptima las parcelas alcanzables.");

            try
            {
                int idGenerado = persistencia.GuardarSimulacion(n, startX, startY, simulador.Secuencia);
                Console.WriteLine($"Simulación guardada en la base de datos con el ID Master Control: {idGenerado}");
                persistencia.GenerarReporteInverso(idGenerado);
            }
            catch (Exception ex)
            {
                Console.WriteLine($"\nOcurrió un error inesperado al interactuar con la base de datos: {ex.Message}");
            }

            Console.WriteLine("Presione cualquier tecla para cerrar el simulador.");
            Console.ReadKey();
        }
    }
}
'@

$simulador = @'
using System;
using System.Collections.Generic;
using DroneSimulator.Models;

namespace DroneSimulator.Services
{
    public class SimuladorVuelo
    {
        private readonly int _n;
        private readonly int _startX;
        private readonly int _startY;
        private readonly int[,] _tablero;
        private readonly List<MovimientoDto> _secuencia;
        private int _totalAlcanzables;

        private readonly int[] _dx = { -2, -2, 2, 2, -1, -1, 1, 1 };
        private readonly int[] _dy = { -1, 1, -1, 1, -2, 2, -2, 2 };

        public List<MovimientoDto> Secuencia => _secuencia;
        public int[,] Tablero => _tablero;

        public SimuladorVuelo(int n, int startX, int startY)
        {
            _n = n;
            _startX = startX;
            _startY = startY;
            _tablero = new int[_n, _n];
            _secuencia = new List<MovimientoDto>();

            for (int i = 0; i < _n; i++)
            {
                for (int j = 0; j < _n; j++)
                {
                    _tablero[i, j] = -1;
                }
            }
        }

        public bool Resolver()
        {
            _totalAlcanzables = CalcularCantidadAlcanzables();
            _tablero[_startX, _startY] = 0;
            _secuencia.Add(new MovimientoDto(0, _startX, _startY));
            return ExplorarPaso(1, _startX, _startY);
        }

        private bool ExplorarPaso(int pasoActual, int xActual, int yActual)
        {
            if (pasoActual == _totalAlcanzables)
            {
                return true;
            }

            var candidatos = ObtenerCandidatosOrdenados(xActual, yActual);
            while (candidatos.Count > 0)
            {
                var candidato = candidatos[0];
                candidatos.RemoveAt(0);

                int nextX = candidato.X;
                int nextY = candidato.Y;
                _tablero[nextX, nextY] = pasoActual;
                _secuencia.Add(new MovimientoDto(pasoActual, nextX, nextY));

                if (ExplorarPaso(pasoActual + 1, nextX, nextY))
                {
                    return true;
                }

                _tablero[nextX, nextY] = -1;
                _secuencia.RemoveAt(_secuencia.Count - 1);
            }

            return false;
        }

        private List<(int X, int Y, int Grado)> ObtenerCandidatosOrdenados(int x, int y)
        {
            var candidatos = new List<(int X, int Y, int Grado)>();
            for (int i = 0; i < 8; i++)
            {
                int nextX = x + _dx[i];
                int nextY = y + _dy[i];
                if (EsValido(nextX, nextY) && _tablero[nextX, nextY] == -1)
                {
                    int grado = ContarSalidasLibres(nextX, nextY);
                    candidatos.Add((nextX, nextY, grado));
                }
            }
            candidatos.Sort((a, b) => a.Grado.CompareTo(b.Grado));
            return candidatos;
        }

        private int ContarSalidasLibres(int x, int y)
        {
            int conteo = 0;
            for (int i = 0; i < 8; i++)
            {
                int nx = x + _dx[i];
                int ny = y + _dy[i];
                if (EsValido(nx, ny) && _tablero[nx, ny] == -1)
                {
                    conteo++;
                }
            }
            return conteo;
        }

        private bool EsValido(int x, int y)
        {
            return x >= 0 && x < _n && y >= 0 && y < _n;
        }

        private int CalcularCantidadAlcanzables()
        {
            var visitados = new bool[_n, _n];
            var fila = new Queue<(int X, int Y)>();
            fila.Enqueue((_startX, _startY));
            visitados[_startX, _startY] = true;
            int contador = 1;

            while (fila.Count > 0)
            {
                var (cx, cy) = fila.Dequeue();
                for (int i = 0; i < 8; i++)
                {
                    int nx = cx + _dx[i];
                    int ny = cy + _dy[i];
                    if (EsValido(nx, ny) && !visitados[nx, ny])
                    {
                        visitados[nx, ny] = true;
                        contador++;
                        fila.Enqueue((nx, ny));
                    }
                }
            }

            return contador;
        }
    }
}
'@

$gestor = @'
using System;
using System.Collections.Generic;
using Npgsql;
using DroneSimulator.Models;

namespace DroneSimulator.Data
{
    public class GestorPersistencia
    {
        private readonly string _connectionString;

        public GestorPersistencia(string connectionString)
        {
            _connectionString = connectionString;
        }

        public void InicializarBaseDeDatos()
        {
            using var conn = new NpgsqlConnection(_connectionString);
            conn.Open();

            string ddlScript = @"
                CREATE TABLE IF NOT EXISTS tb_master_control (
                    id SERIAL PRIMARY KEY,
                    fecha_sistema TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
                    tamano_n INT NOT NULL,
                    despegue_x INT NOT NULL,
                    despegue_y INT NOT NULL
                );
                CREATE TABLE IF NOT EXISTS tb_det_log (
                    id SERIAL PRIMARY KEY,
                    master_id INT NOT NULL,
                    paso_etiqueta INT NOT NULL,
                    coordenada_x INT NOT NULL,
                    coordenada_y INT NOT NULL,
                    CONSTRAINT fk_det_log_master FOREIGN KEY (master_id)
                        REFERENCES tb_master_control (id) ON DELETE CASCADE
                );";

            using var cmd = new NpgsqlCommand(ddlScript, conn);
            cmd.ExecuteNonQuery();
        }

        public int GuardarSimulacion(int n, int startX, int startY, List<MovimientoDto> secuencia)
        {
            using var conn = new NpgsqlConnection(_connectionString);
            conn.Open();
            using var trans = conn.BeginTransaction();

            try
            {
                int masterId;
                string sqlMaster = @"
                    INSERT INTO tb_master_control (tamano_n, despegue_x, despegue_y)
                    VALUES (@n, @x, @y)
                    RETURNING id;";

                using (var cmdMaster = new NpgsqlCommand(sqlMaster, conn, trans))
                {
                    cmdMaster.Parameters.AddWithValue("@n", n);
                    cmdMaster.Parameters.AddWithValue("@x", startX);
                    cmdMaster.Parameters.AddWithValue("@y", startY);
                    masterId = Convert.ToInt32(cmdMaster.ExecuteScalar());
                }

                string sqlDetalle = @"
                    INSERT INTO tb_det_log (master_id, paso_etiqueta, coordenada_x, coordenada_y)
                    VALUES (@masterId, @pasoEtiqueta, @cx, @cy);";

                for (int i = 0; i < secuencia.Count; i++)
                {
                    var mov = secuencia[i];
                    int pasoOfuscado = mov.Paso % 2 == 0 ? mov.Paso * 2 : mov.Paso * -1;

                    using var cmdDet = new NpgsqlCommand(sqlDetalle, conn, trans);
                    cmdDet.Parameters.AddWithValue("@masterId", masterId);
                    cmdDet.Parameters.AddWithValue("@pasoEtiqueta", pasoOfuscado);
                    cmdDet.Parameters.AddWithValue("@cx", mov.X);
                    cmdDet.Parameters.AddWithValue("@cy", mov.Y);
                    cmdDet.ExecuteNonQuery();
                }

                trans.Commit();
                return masterId;
            }
            catch
            {
                trans.Rollback();
                throw;
            }
        }

        public void GenerarReporteInverso(int masterId)
        {
            string sqlReporte = @"
                SELECT id, paso_etiqueta, coordenada_x, coordenada_y
                FROM tb_det_log
                WHERE master_id = @masterId
                ORDER BY id DESC
                LIMIT 5;";

            using var conn = new NpgsqlConnection(_connectionString);
            conn.Open();
            using var cmd = new NpgsqlCommand(sqlReporte, conn);
            cmd.Parameters.AddWithValue("@masterId", masterId);

            using var reader = cmd.ExecuteReader();
            Console.WriteLine("\n=======================================================");
            Console.WriteLine("REPORTE INVERSO: ÚLTIMOS 5 PASOS RECONSTRUIDOS");
            Console.WriteLine("=======================================================");
            Console.WriteLine($"{"ID Registro",-15} | {"Paso Real",-12} | {"Coordenadas (X, Y)",-20}");
            Console.WriteLine("-------------------------------------------------------");

            while (reader.Read())
            {
                int idReg = reader.GetInt32(0);
                int pasoOfuscado = reader.GetInt32(1);
                int cx = reader.GetInt32(2);
                int cy = reader.GetInt32(3);
                int pasoReal = pasoOfuscado < 0 ? -pasoOfuscado : pasoOfuscado / 2;
                Console.WriteLine($"{idReg,-15} | {pasoReal,-12} | ({cx}, {cy})");
            }

            Console.WriteLine("=======================================================\n");
        }
    }
}
'@

$csproj = @'
<Project Sdk="Microsoft.NET.Sdk">

  <PropertyGroup>
    <OutputType>Exe</OutputType>
    <TargetFramework>net10.0</TargetFramework>
    <RootNamespace>Dron_Parcial</RootNamespace>
    <ImplicitUsings>enable</ImplicitUsings>
    <Nullable>enable</Nullable>
  </PropertyGroup>

  <ItemGroup>
    <PackageReference Include="Microsoft.Extensions.Configuration" Version="8.0.0" />
    <PackageReference Include="Microsoft.Extensions.Configuration.FileExtensions" Version="8.0.0" />
    <PackageReference Include="Microsoft.Extensions.Configuration.Json" Version="8.0.0" />
    <PackageReference Include="Npgsql" Version="8.1.0" />
  </ItemGroup>

  <ItemGroup>
    <None Update="appsettings.json">
      <CopyToOutputDirectory>PreserveNewest</CopyToOutputDirectory>
    </None>
  </ItemGroup>

</Project>
'@

$app = @'
{
  "ConnectionStrings": {
    "PostgresConnection": "Host=localhost;Port=5432;Database=dron_parcial;Username=postgres;Password=postgres"
  }
}
'@

Set-Content -Path '.\Program.cs' -Value $program -Encoding UTF8
Set-Content -Path '.\Services\SimuladorVuelo.cs' -Value $simulador -Encoding UTF8
Set-Content -Path '.\Data\GestorPersistencia.cs' -Value $gestor -Encoding UTF8
Set-Content -Path '.\Dron Parcial.csproj' -Value $csproj -Encoding UTF8
Set-Content -Path '.\appsettings.json' -Value $app -Encoding UTF8
Write-Host 'done'"