import { createRoot } from "react-dom/client";
import PanelShowcase from "@/components/panel-showcase";
import FeatureCards from "@/components/feature-cards";
import HalftoneWordmarkFooter from "@/components/ui/halftone-wordmark-footer";
import LogoVidrio from "@/components/logo-vidrio";

const panel = document.getElementById("panel-showcase");
if (panel) createRoot(panel).render(<PanelShowcase />);

const features = document.getElementById("feature-cards");
if (features) createRoot(features).render(<FeatureCards />);

const logoVidrio = document.getElementById("logo-vidrio");
if (logoVidrio) createRoot(logoVidrio).render(<LogoVidrio className="h-full w-full" />);

const footer = document.getElementById("site-footer");
if (footer) createRoot(footer).render(<HalftoneWordmarkFooter />);
