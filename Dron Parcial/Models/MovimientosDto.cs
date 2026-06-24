namespace DroneSimulator.Models
{
    public class MovimientoDto
    {
        public int Paso { get; set; }
        public int X { get; set; }
        public int Y { get; set; }

        public MovimientoDto(int paso, int x, int y)
        {
            Paso = paso;
            X = x;
            Y = y;
        }
    }
}