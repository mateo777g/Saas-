// Los iconos de trazo del panel de Flet (panel/assets/iconos/*.svg), tal cual: viewBox 24,
// trazo 1.7, puntas redondas. Solo va lo de adentro del <svg>; Icono.svelte pone el resto y
// el color sale de currentColor. Generado de esos archivos: si cambia uno, se regenera. Los
// pocos que en Flet llevan otro grosor (check 3, mas 2, check-fino y flecha 2.2) lo traen en
// cada trazo, que le gana al 1.7 de Icono.svelte.
export const ICONOS: Record<string, string> = {
  'actualizar': '<path d="M21 12a9 9 0 1 1-3-6.7L21 8"></path><path d="M21 3v5h-5"></path>',
  'agregar': '<circle cx="12" cy="12" r="9"></circle><path d="M12 8v8"></path><path d="M8 12h8"></path>',
  'ajustes': '<circle cx="12" cy="12" r="3"></circle><path d="M19.4 15a1.7 1.7 0 0 0 .3 1.8l.1.1a2 2 0 1 1-2.8 2.8l-.1-.1a1.7 1.7 0 0 0-1.8-.3 1.7 1.7 0 0 0-1 1.5V21a2 2 0 1 1-4 0v-.1a1.7 1.7 0 0 0-1.1-1.5 1.7 1.7 0 0 0-1.8.3l-.1.1a2 2 0 1 1-2.8-2.8l.1-.1a1.7 1.7 0 0 0 .3-1.8 1.7 1.7 0 0 0-1.5-1H3a2 2 0 1 1 0-4h.1a1.7 1.7 0 0 0 1.5-1.1 1.7 1.7 0 0 0-.3-1.8l-.1-.1a2 2 0 1 1 2.8-2.8l.1.1a1.7 1.7 0 0 0 1.8.3H9a1.7 1.7 0 0 0 1-1.5V3a2 2 0 1 1 4 0v.1a1.7 1.7 0 0 0 1 1.5 1.7 1.7 0 0 0 1.8-.3l.1-.1a2 2 0 1 1 2.8 2.8l-.1.1a1.7 1.7 0 0 0-.3 1.8V9a1.7 1.7 0 0 0 1.5 1H21a2 2 0 1 1 0 4h-.1a1.7 1.7 0 0 0-1.5 1z"></path>',
  'alerta': '<path d="M12 9v4"></path><path d="M12 17h.01"></path><path d="M10.3 3.9L1.8 18a2 2 0 0 0 1.7 3h17a2 2 0 0 0 1.7-3L13.7 3.9a2 2 0 0 0-3.4 0z"></path>',
  'anterior': '<path d="M15 18l-6-6 6-6"></path>',
  'ayuda': '<circle cx="12" cy="12" r="9"></circle><path d="M9.1 9a3 3 0 0 1 5.8 1c0 2-3 3-3 3"></path><path d="M12 17h.01"></path>',
  'biblio': '<rect x="3" y="3" width="18" height="18" rx="2"></rect><circle cx="9" cy="9" r="2"></circle><path d="M21 15l-5-5L5 21"></path>',
  'buscar': '<circle cx="11" cy="11" r="7"></circle><path d="M20 20l-3.5-3.5"></path>',
  'candado': '<rect x="4" y="11" width="16" height="10" rx="2"></rect><path d="M8 11V7a4 4 0 0 1 8 0v4"></path>',
  'carpeta-abrir': '<path d="M3 7a2 2 0 0 1 2-2h4l2 2h8a2 2 0 0 1 2 2v1"></path><path d="M3 7v10a2 2 0 0 0 2 2h12.5a2 2 0 0 0 1.9-1.4l2-6A1 1 0 0 0 20.5 10H7.3a2 2 0 0 0-1.9 1.4L3 19"></path>',
  'carpeta': '<path d="M3 7a2 2 0 0 1 2-2h4l2 2h8a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z"></path>',
  'cerrar': '<path d="M18 6L6 18"></path><path d="M6 6l12 12"></path>',
  'check-fino': '<path stroke-width="2.2" d="M5 12l5 5L20 7"></path>',
  'check': '<path stroke-width="3" d="M5 12l5 5L20 7"></path>',
  'combinar': '<rect x="8" y="8" width="13" height="13" rx="2"></rect><path d="M4 16V5a1 1 0 0 1 1-1h11"></path><path d="M14.5 11.5v6"></path><path d="M11.5 14.5h6"></path>',
  'contraste': '<circle cx="12" cy="12" r="9"></circle><path d="M12 3a9 9 0 0 1 0 18z" fill="currentColor"></path>',
  'copiar': '<rect x="9" y="9" width="12" height="12" rx="2"></rect><path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1"></path>',
  'correo': '<rect x="3" y="5" width="18" height="14" rx="2"></rect><path d="M3 7l9 6 9-6"></path>',
  'crear': '<path d="M12 20h9"></path><path d="M16.5 3.5a2.1 2.1 0 0 1 3 3L7 19l-4 1 1-4z"></path>',
  'datos': '<ellipse cx="12" cy="5" rx="8" ry="3"></ellipse><path d="M4 5v14c0 1.7 3.6 3 8 3s8-1.3 8-3V5"></path><path d="M4 12c0 1.7 3.6 3 8 3s8-1.3 8-3"></path>',
  'derecha': '<path d="M5 12h14"></path><path d="M13 6l6 6-6 6"></path>',
  'eliminar': '<path d="M3 6h18"></path><path d="M8 6V4h8v2"></path><path d="M19 6l-1 14H6L5 6"></path><path d="M10 11v6"></path><path d="M14 11v6"></path>',
  'entrar': '<path d="M15 3h4a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2h-4"></path><path d="M10 17l5-5-5-5"></path><path d="M15 12H3"></path>',
  'exportar': '<path d="M12 4v11"></path><path d="M7.5 10.5L12 15l4.5-4.5"></path><path d="M5 20h14"></path>',
  'flecha': '<path stroke-width="2.2" d="M12 19V5"></path><path stroke-width="2.2" d="M5 12l7-7 7 7"></path>',
  'guardar': '<path d="M5 3h11l3 3v13a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2z"></path><path d="M8 3v5h7V3"></path><path d="M8 21v-6h8v6"></path>',
  'historia': '<rect x="7" y="2" width="10" height="20" rx="2"></rect>',
  'historial': '<path d="M3 12a9 9 0 1 0 3-6.7L3 8"></path><path d="M3 3v5h5"></path><path d="M12 7v5l3 2"></path>',
  'hoy': '<rect x="3" y="4" width="18" height="17" rx="2"></rect><path d="M16 2v4"></path><path d="M8 2v4"></path><path d="M3 10h18"></path><rect x="7" y="13" width="4" height="4" rx="0.5"></rect>',
  'ia': '<path d="M12 3l1.8 4.7L18.5 9.5l-4.7 1.8L12 16l-1.8-4.7L5.5 9.5l4.7-1.8z"></path><path d="M19 15l.8 2.2L22 18l-2.2.8L19 21l-.8-2.2L16 18l2.2-.8z"></path>',
  'info': '<circle cx="12" cy="12" r="9"></circle><path d="M12 11v5"></path><path d="M12 8h.01"></path>',
  'inicio': '<rect x="3" y="3" width="7" height="7" rx="1.5"></rect><rect x="14" y="3" width="7" height="7" rx="1.5"></rect><rect x="3" y="14" width="7" height="7" rx="1.5"></rect><rect x="14" y="14" width="7" height="7" rx="1.5"></rect>',
  'luna': '<path d="M20 14.5A8 8 0 1 1 9.5 4a6.5 6.5 0 0 0 10.5 10.5z"></path>',
  'mas': '<path stroke-width="2" d="M12 5v14"></path><path stroke-width="2" d="M5 12h14"></path>',
  'menu': '<path d="M8 6h13"></path><path d="M8 12h13"></path><path d="M8 18h13"></path><circle cx="4" cy="6" r="1"></circle><circle cx="4" cy="12" r="1"></circle><circle cx="4" cy="18" r="1"></circle>',
  'mes': '<rect x="3" y="3" width="18" height="18" rx="2"></rect><path d="M8 17v-5"></path><path d="M12 17V8"></path><path d="M16 17v-3"></path>',
  'mesas': '<path d="M3 9h18"></path><path d="M5 9v10"></path><path d="M19 9v10"></path><path d="M8 5h8"></path>',
  'oculto': '<path d="M3 3l18 18"></path><path d="M10.6 5.1A10 10 0 0 1 12 5c6.5 0 10 7 10 7a17 17 0 0 1-3.2 4.1"></path><path d="M6.6 6.6A17 17 0 0 0 2 12s3.5 7 10 7a9.7 9.7 0 0 0 5.4-1.6"></path><path d="M9.9 9.9a3 3 0 0 0 4.2 4.2"></path>',
  'ojo': '<path d="M2 12s3.5-7 10-7 10 7 10 7-3.5 7-10 7S2 12 2 12z"></path><circle cx="12" cy="12" r="3"></circle>',
  'post': '<rect x="5" y="3" width="14" height="17.5" rx="2"></rect>',
  'salir': '<path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4"></path><path d="M16 17l5-5-5-5"></path><path d="M21 12H9"></path>',
  'semana': '<path d="M3 3v18h18"></path><path d="M7 15l4-4 3 3 5-6"></path>',
  'siguiente': '<path d="M9 18l6-6-6-6"></path>',
  'sol': '<circle cx="12" cy="12" r="4"></circle><path d="M12 2v2"></path><path d="M12 20v2"></path><path d="M4.9 4.9l1.4 1.4"></path><path d="M17.7 17.7l1.4 1.4"></path><path d="M2 12h2"></path><path d="M20 12h2"></path><path d="M4.9 19.1l1.4-1.4"></path><path d="M17.7 6.3l1.4-1.4"></path>',
  'tienda': '<path d="M3 9l1.5-5h15L21 9"></path><path d="M3 9h18"></path><path d="M5 9v11h14V9"></path><path d="M10 20v-6h4v6"></path>',
  'volver': '<path d="M3 12a9 9 0 1 0 3-6.7L3 8"></path><path d="M3 3v5h5"></path>',
  // Nuevos, de las maquetas aprobadas (panel de Fragmentless Tbt7H3G1QRXykzNKe1GXHh, Inicio del
  // gerente 5SVLK2avzLCq5TaW6mrqq6, suscripción terminada X4t62jG6dDG1hKfR4ZyyXZ), en el mismo
  // estilo: no existen en Flet.
  'abajo': '<path d="M6 9l6 6 6-6"></path>',
  // La flecha de subir una categoría (maqueta del Menú CC2rrjbgxC2yykNa33a3sA).
  'arriba': '<path d="M6 15l6-6 6 6"></path>',
  // La palomita de la sucursal en la que está, con el trazo de siempre (la de Flet lleva 3).
  'check-delgado': '<path d="M5 12l5 5L20 7"></path>',
  'mensaje': '<path d="M7.9 20A9 9 0 1 0 4 16.1L2 22z"></path>',
  'calendario-mas': '<rect x="3" y="4" width="18" height="17" rx="2"></rect><path d="M16 2v4"></path><path d="M8 2v4"></path><path d="M3 10h18"></path><path d="M12 13v5"></path><path d="M9.5 15.5h5"></path>',
  'usuario-mas': '<path d="M15 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2"></path><circle cx="8.5" cy="7" r="4"></circle><path d="M19 8v6"></path><path d="M22 11h-6"></path>',
  'usuarios': '<path d="M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2"></path><circle cx="9" cy="7" r="4"></circle><path d="M22 21v-2a4 4 0 0 0-3-3.87"></path><path d="M16 3.13a4 4 0 0 1 0 7.75"></path>',
  'usuario-menos': '<path d="M15 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2"></path><circle cx="8.5" cy="7" r="4"></circle><path d="M22 11h-6"></path>',
  'usuario-check': '<path d="M15 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2"></path><circle cx="8.5" cy="7" r="4"></circle><path d="M16 11l2 2 4-4"></path>',
  // Los de Empleados y el aparato del equipo (maqueta 36iXMMqXCfVv4NuVR7vNSc), de Lucide
  // (licencia ISC) con el mismo trazo: el celular, la tableta, dar de baja, desligar y la tecla
  // de borrar del PIN.
  'celular': '<rect x="5" y="2" width="14" height="20" rx="2"></rect><path d="M12 18h.01"></path>',
  'tableta': '<rect x="4" y="2" width="16" height="20" rx="2"></rect><path d="M12 18h.01"></path>',
  'baja': '<path d="M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2"></path><circle cx="9" cy="7" r="4"></circle><path d="M22 11h-6"></path>',
  'desligar': '<path d="m18.84 12.25 1.72-1.71a5 5 0 0 0-7.07-7.07l-1.72 1.71"></path><path d="m5.17 11.75-1.71 1.71a5 5 0 0 0 7.07 7.07l1.71-1.71"></path><path d="M8 2v3"></path><path d="M2 8h3"></path><path d="M16 19v3"></path><path d="M19 16h3"></path>',
  'borrar': '<path d="M10 5a2 2 0 0 0-1.344.519l-6.328 5.74a1 1 0 0 0 0 1.481l6.328 5.741A2 2 0 0 0 10 19h10a2 2 0 0 0 2-2V7a2 2 0 0 0-2-2z"></path><path d="m12 9 6 6"></path><path d="m18 9-6 6"></path>',
  // El − del mínimo y el máximo de un grupo (maqueta de Opciones y áreas GhrEVWPmevfBZtWzi4exKi),
  // con el grosor del + de Flet.
  'menos': '<path stroke-width="2" d="M5 12h14"></path>',
  // Los del punto de venta (maqueta Mesero y cocina TYq97pKacRCYBqcvRp1bZ2), de Lucide (licencia
  // ISC) con el mismo trazo.
  'puntos': '<circle cx="5" cy="12" r="1.2"></circle><circle cx="12" cy="12" r="1.2"></circle><circle cx="19" cy="12" r="1.2"></circle>',
  'cuenta': '<path d="M6 2h12v20l-3-2-3 2-3-2-3 2z"></path><path d="M9 7h6"></path><path d="M9 11h6"></path><path d="M9 15h4"></path>',
  'cambiar': '<path d="M17 3l4 4-4 4"></path><path d="M3 7h18"></path><path d="M7 21l-4-4 4-4"></path><path d="M21 17H3"></path>',
  'juntar': '<path d="M8 6l4-4 4 4"></path><path d="M12 2v10.3a4 4 0 0 1-1.2 2.8L4 22"></path><path d="M20 22l-5-5"></path>',
  'bolsa': '<path d="M6 2L3 6v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2V6l-3-4z"></path><path d="M3 6h18"></path><path d="M16 10a4 4 0 0 1-8 0"></path>',
  'moto': '<circle cx="5.5" cy="17.5" r="3.5"></circle><circle cx="18.5" cy="17.5" r="3.5"></circle><path d="M15 6h2l3 7.5"></path><path d="M5.5 17.5L9 10h6l3.5 7.5"></path>',
  'sinred': '<path d="M2 2l20 20"></path><path d="M8.5 16.5a5 5 0 0 1 7 0"></path><path d="M2 8.8a15 15 0 0 1 4.2-2.6"></path><path d="M10.7 5.1A15 15 0 0 1 22 8.8"></path><path d="M5 12.9a10 10 0 0 1 5.2-2.8"></path><path d="M16.8 13.6a10 10 0 0 1 2.2-.7"></path><path d="M12 20h.01"></path>',
  'regresar': '<path d="M9 14L4 9l5-5"></path><path d="M4 9h10.5a5.5 5.5 0 0 1 0 11H11"></path>',
  'afuera': '<path d="M15 3h6v6"></path><path d="M10 14L21 3"></path><path d="M18 13v6a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h6"></path>',
  'billete': '<rect x="2" y="6" width="20" height="12" rx="2"></rect><circle cx="12" cy="12" r="2"></circle><path d="M6 12h.01"></path><path d="M18 12h.01"></path>',
  'cocina': '<path d="M17 21a1 1 0 0 0 1-1v-5.35c0-.457.316-.844.727-1.041a4 4 0 0 0-2.134-7.589 5 5 0 0 0-9.186 0 4 4 0 0 0-2.134 7.588c.411.198.727.585.727 1.041V20a1 1 0 0 0 1 1Z"></path><path d="M6 17h12"></path>',
  'reloj': '<circle cx="12" cy="12" r="9"></circle><path d="M12 7v5l3 2"></path>',
  // Los de la caja (maqueta La caja FKj5RPPYE1tz6dcaU6F4kX): tarjeta y banco de Lucide (licencia
  // ISC); corte y propina dibujados con el mismo trazo.
  'tarjeta': '<rect x="2" y="5" width="20" height="14" rx="2"></rect><path d="M2 10h20"></path>',
  'banco': '<path d="M3 21h18"></path><path d="M5 21V11"></path><path d="M19 21V11"></path><path d="M9.5 21V11"></path><path d="M14.5 21V11"></path><path d="M12 3l9 5H3z"></path>',
  'corte': '<rect x="4" y="3" width="16" height="18" rx="2"></rect><path d="M8 7h8"></path><path d="M8 11h8"></path><path d="M8 15h5"></path>',
  'propina': '<circle cx="12" cy="12" r="9"></circle><path d="M15 9.5a3 2.5 0 0 0-3-1.5c-1.7 0-3 .9-3 2s1.3 1.8 3 2 3 .9 3 2-1.3 2-3 2a3 2.5 0 0 1-3-1.5"></path><path d="M12 6v2"></path><path d="M12 16v2"></path>',
  'porcentaje': '<path d="M19 5L5 19"></path><circle cx="6.5" cy="6.5" r="2.5"></circle><circle cx="17.5" cy="17.5" r="2.5"></circle>',
  // Las dos flechas de «Vendido hoy» contra ayer (maqueta Agente IA KznKZdgQbLTZGs1EwVMvga).
  'flecha-sube': '<path d="M12 19V5"></path><path d="M6 11l6-6 6 6"></path>',
  'flecha-baja': '<path d="M12 5v14"></path><path d="M6 13l6 6 6-6"></path>',
};
