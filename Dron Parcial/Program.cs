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

            var builder = new ConfigurationBuilder()
                .SetBasePath(Directory.GetCurrentDirectory())
                .AddJsonFile("appsettings.json", optional: false, reloadOnChange: true);

            IConfiguration configuration = builder.Build();
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
                    Console.Write(tablero[i, j] == -1 ? ".\t" : $"{tablero[i, j]}\t");
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
                Console.WriteLine($"\nOcurrió un error inesperado al interactuar con la Base de Datos: {ex.Message}");
            }

            Console.WriteLine("Presione cualquier tecla para cerrar el simulador.");
            Console.ReadKey();
        }
    }
}