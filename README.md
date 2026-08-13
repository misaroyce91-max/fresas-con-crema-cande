# Fresas con Crema Cande

Aplicación mobile-first de pedidos, fidelización y operación para Fresas con Crema Cande. Funciona inmediatamente en modo demo; el esquema para Supabase está incluido.

## Iniciar

```bash
npm install
npm run dev
```

Abre `http://localhost:3000`. El panel está en `http://localhost:3000/admin`; en demo acepta cualquier correo y contraseña.

## Variables de entorno

Copia `.env.example` como `.env.local` y completa:

- `NEXT_PUBLIC_SUPABASE_URL`: URL del proyecto Supabase.
- `NEXT_PUBLIC_SUPABASE_ANON_KEY`: clave pública anon.
- `SUPABASE_SERVICE_ROLE_KEY`: solo para código de servidor, nunca para el navegador.
- `NEXT_PUBLIC_BUSINESS_WHATSAPP`: teléfono del negocio con código de país.

Sin estas variables, la aplicación usa datos demo y `localStorage` para el carrito y último pedido.

## Conectar Supabase

1. Crea un proyecto en Supabase.
2. Ejecuta `supabase/schema.sql` en SQL Editor.
3. Copia URL y anon key desde Project Settings > API a `.env.local`.
4. Configura Auth con teléfono o correo.
5. Sustituye gradualmente `lib/data.ts` por consultas a `lib/supabase.ts`.
6. Implementa la confirmación de pedido en una Server Action o Edge Function. Esa operación debe calcular totales y puntos en servidor, en una sola transacción.

## Incluido

- Inicio visual, catálogo personalizable, carrito persistente y checkout.
- Confirmación con puntos ganados y mensaje estructurado para WhatsApp.
- Rewards, niveles Fresa/Gold/VIP, cuenta e historial demo.
- Panel `/admin` con login demo, KPIs, semanas, productos, clientes e inteligencia comercial.
- Esquema relacional, índices, RLS, reglas configurables y vista semanal que conserva todo el histórico.
- Tres fotografías originales de producto generadas para el proyecto.

## Para producción

- Reemplazar login demo por Supabase Auth y rol `admin` en `app_metadata`.
- Crear RPC/Edge Function transaccional para pedidos, puntos y canjes.
- Conectar WhatsApp Business, pagos con tarjeta/Mercado Pago y tarifas reales de entrega.
- Añadir tablas `branches` y `admin_users`; los campos `branch_id` ya preparan el modelo multisucursal.
- Agregar inventario, notificaciones, pruebas E2E y monitoreo.

## Primer recorrido de prueba

Inicio → Menú → personalizar producto → Carrito → Checkout → confirmar → Pedidos → Rewards. Después entra a `/admin` y prueba filtros, comparativas y búsqueda de clientes.

## Cande Repartidor PWA

Abre `/driver` por HTTPS en Chrome Android, inicia sesión y usa **Agregar a pantalla principal** o **Instalar aplicación**. El manifiesto, los iconos, el modo standalone y el service worker ya están configurados.

Las alertas con la app abierta usan sonido, vibración y Notification API. Para Web Push cerrado falta:

1. Generar un par VAPID y configurar `NEXT_PUBLIC_VAPID_PUBLIC_KEY`, `VAPID_PRIVATE_KEY` y `VAPID_SUBJECT`.
2. Guardar la suscripción del navegador en `push_subscriptions` asociada al courier autenticado.
3. Crear una Supabase Edge Function que firme y envíe el push al insertarse una `delivery_request`.
4. Configurar Supabase Auth para cada repartidor y asignar `app_metadata.role = DRIVER`.

La función SQL `accept_delivery_request(uuid)` realiza la aceptación atómica: bloquea al repartidor, cambia la solicitud solo si sigue abierta, crea la asignación y marca al repartidor como ocupado. Una segunda aceptación falla con `DELIVERY_ALREADY_TAKEN`.
