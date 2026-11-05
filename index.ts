import express, { Request, Response } from 'express';
import { Pool } from 'pg';

const app = express();
const port = 3000;

app.use(express.json());

// Configuración de la base de datos usando variables de entorno
const pool = new Pool({
    host: process.env.DB_HOST,
    user: process.env.DB_USER,
    password: process.env.DB_PASSWORD,
    database: process.env.DB_NAME,
    port: 5432,
    ssl: {
        rejectUnauthorized: false
    }
});

// Crear la tabla automáticamente si no existe al arrancar
const initDB = async () => {
    try {
        await pool.query(`
            CREATE TABLE IF NOT EXISTS tasks (
                id SERIAL PRIMARY KEY,
                tarea VARCHAR(255) NOT NULL
            );
        `);
        console.log("Tabla 'tasks' lista en PostgreSQL.");
    } catch (error) {
        console.error("Error al inicializar la base de datos:", error);
    }
};

initDB();

app.get('/tasks', async (req: Request, res: Response) => {
    try {
        const result = await pool.query('SELECT * FROM tasks;');
        res.json({ tasks: result.rows });
    } catch (error) {
        console.error(error);
        res.status(500).json({ error: "Error al obtener las tareas" });
    }
});

app.post('/tasks', async (req: Request, res: Response) => {
    const { tarea } = req.body;
    
    if (tarea) {
        try {
            const result = await pool.query(
                'INSERT INTO tasks (tarea) VALUES ($1) RETURNING *;',
                [tarea]
            );
            res.status(201).json({ message: "Tarea agregada con éxito", task: result.rows[0] });
        } catch (error) {
            console.error(error);
            res.status(500).json({ error: "Error al guardar la tarea" });
        }
    } else {
        res.status(400).json({ error: "Falta el campo 'tarea' en el cuerpo de la petición" });
    }
});

app.listen(port, () => {
    console.log(`Servidor corriendo en el puerto ${port}`);
});
