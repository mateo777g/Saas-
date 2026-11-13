import { mount } from 'svelte';
import './estilos.css';
import Menu from './Menu.svelte';
// Después de los estilos de cada pieza, como en la maqueta de «Tu menú en línea»: las formas van encima de ellos.
import './formas.css';

mount(Menu, { target: document.getElementById('menu')! });
