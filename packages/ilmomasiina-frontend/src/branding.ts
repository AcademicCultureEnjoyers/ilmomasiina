export type Branding = {
  headerTitle: string;
  headerTitleShort: string;
  footerGdprText: string;
  footerGdprLink: string;
  footerHomeText: string;
  footerHomeLink: string;
  loginPlaceholderEmail: string;
};

// The following strings can be changed here in code.

const branding: Branding = {
  headerTitle: "Academic Culture Enjoyers",
  headerTitleShort: "ACE",
  footerGdprText: "Privacy Policy",
  footerGdprLink: "https://academicculture.org/privacy",
  footerHomeText: "Home",
  footerHomeLink: "https://academicculture.org",
  loginPlaceholderEmail: "admin@academicculture.org",
};

export default branding;
