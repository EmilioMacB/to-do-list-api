import express, { Request, Response } from 'express';

const app = express();
const port = 3000;

// Middleware para parsear JSON
app.use(express.json());

// Lista en memoria
const tasks: string[] = [];

app.get('/tasks', (req: Request, res: Response) => {
    res.json({ tasks });
});

app.post('/tasks', (req: Request, res: Response) => {
    const { tarea } = req.body;
    
    if (tarea) {
        tasks.push(tarea);
        res.status(201).json({ message: "Tarea agregada con éxito", tasks });
    } else {
        res.status(400).json({ error: "Falta el campo 'tarea' en el cuerpo de la petición" });
    }
});

app.listen(port, () => {
    console.log(`Servidor corriendo en el puerto ${port}`);
});
