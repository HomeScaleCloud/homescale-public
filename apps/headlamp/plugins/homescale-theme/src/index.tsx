import { AppLogoProps, registerAppLogo, registerAppTheme } from '@kinvolk/headlamp-plugin/lib';
import { LOGO_BANNER_DATA_URI, LOGO_ICON_DATA_URI } from './assets';

// Navy sampled from media/homescale-{icon,transparent,banner}.png in the repo
// root; accent is the requested selection/highlight colour.
const HOMESCALE_NAVY = '#0A0F18';
const HOMESCALE_ACCENT = '#4789CF';

function HomeScaleLogo(props: AppLogoProps) {
  const { logoType, className, sx } = props;

  // The banner already has the icon + "HomeScale" wordmark on the brand navy,
  // which matches navbar.background/sidebar.background below, so it blends
  // in regardless of which base theme (light/dark) is active.
  return (
    <img
      className={className}
      style={{ height: 32, width: 'auto', ...(sx as React.CSSProperties) }}
      src={logoType === 'large' ? LOGO_BANNER_DATA_URI : LOGO_ICON_DATA_URI}
      alt="HomeScale"
    />
  );
}

registerAppLogo(HomeScaleLogo);

const sidebarAndNavbar = {
  sidebar: {
    background: HOMESCALE_NAVY,
    color: '#CBD5E1',
    selectedBackground: HOMESCALE_ACCENT,
    selectedColor: '#FFFFFF',
    actionBackground: '#1E293B',
  },
  navbar: {
    background: HOMESCALE_NAVY,
    color: '#F8FAFC',
  },
  buttonTextTransform: 'none' as const,
  radius: 8,
};

registerAppTheme({
  name: 'homescale',
  base: 'light',
  primary: HOMESCALE_ACCENT,
  secondary: '#F1F5F9',
  ...sidebarAndNavbar,
});

registerAppTheme({
  name: 'homescale-dark',
  base: 'dark',
  primary: HOMESCALE_ACCENT,
  secondary: HOMESCALE_NAVY,
  ...sidebarAndNavbar,
});
