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
                const string sqlMaster = @"
INSERT INTO tb_master_control (tamano_n, despegue_x, despegue_y)
VALUES (@n, @x, @y)
RETURNING id;";

                int masterId;
                using (var cmdMaster = new NpgsqlCommand(sqlMaster, conn, trans))
                {
                    cmdMaster.Parameters.AddWithValue("@n", n);
                    cmdMaster.Parameters.AddWithValue("@x", startX);
                    cmdMaster.Parameters.AddWithValue("@y", startY);
                    masterId = Convert.ToInt32(cmdMaster.ExecuteScalar());
                }

                const string sqlDetalle = @"
INSERT INTO tb_det_log (master_id, paso_etiqueta, coordenada_x, coordenada_y)
VALUES (@masterId, @pasoEtiqueta, @cx, @cy);";

                for (int i = 0; i < secuencia.Count; i++)
                {
                    var mov = secuencia[i];
                    int pasoOfuscado = mov.Paso % 2 == 0 ? mov.Paso * 2 : -mov.Paso;

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
            const string sqlReporte = @"
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
