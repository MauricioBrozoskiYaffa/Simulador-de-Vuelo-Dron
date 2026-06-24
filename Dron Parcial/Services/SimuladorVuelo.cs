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
