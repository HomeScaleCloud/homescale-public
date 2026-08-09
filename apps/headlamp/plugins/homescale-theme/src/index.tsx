import {
  AppLogoProps,
  CommonComponents,
  K8s,
  registerAppLogo,
  registerAppTheme,
  registerRoute,
  registerSidebarEntry,
} from '@kinvolk/headlamp-plugin/lib';
import React from 'react';
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

// Links out to the real ArgoCD UI for the selected cluster instead of
// proxying through the k8s API: argocd-server's Service always has two
// named ports (http+https, both aliasing the same container port), and an
// unqualified `services/proxy` request to a multi-port Service fails with
// "no endpoints available" regardless of RBAC -- a k8s apiserver limitation
// (see https://github.com/kubernetes/kubernetes/issues/20070), not
// something fixable on our end.
function ArgoCDRedirect() {
  const cluster = K8s.useCluster();
  const target = cluster ? `https://argocd-server.argocd.${cluster}REDACTED` : null;

  React.useEffect(() => {
    if (target) {
      window.location.assign(target);
    }
  }, [target]);

  return (
    <>
      <CommonComponents.SectionHeader title="ArgoCD" />
      <CommonComponents.SectionBox>
        {target ? (
          <p>
            Opening <a href={target}>{target}</a>…
          </p>
        ) : (
          <p>No cluster selected.</p>
        )}
      </CommonComponents.SectionBox>
    </>
  );
}

registerSidebarEntry({
  parent: null,
  name: 'argocd',
  label: 'ArgoCD',
  url: '/argocd',
  icon: 'mdi:git',
});

registerRoute({
  path: '/argocd',
  sidebar: 'argocd',
  name: 'argocd',
  exact: true,
  component: () => <ArgoCDRedirect />,
});
