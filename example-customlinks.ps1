### Create example $mylinks variable with our branding menu structure

$mylinks = [PSCustomObject]@(
    # Override the default 'about' link to redirect to https://my.company.com/about/:
    @{
        name="about";
        menuItemType="override";
        url="https://my.company.com/about/"
    },
    # Add the section name 'Support':
    @{
        name="Support";
        menuItemType="section"
    },
    # Add the 'Help Desk' link:
    @{
        name="Help Desk";
        menuItemType="link";
        url="https://my.company.com/helpdesk/"
    },
    # Add the 'Contact Us' link:
    @{
        name="Contact Us";
        menuItemType="link";
        url="mailto:contact@my.company.com?subject=Web Support"
    },
    # Add the Separator:
    @{
        menuItemType="separator"
    },
    # Add the 'Services' group:
    @{
        name="Services";
        menuItemType="section"
    },
    # Add the 'Other services' link:
    @{
        name="Other services";
        menuItemType="link";
        url="https://my.company.com/services/"
    },
    # Add the 2nd Separator:
    @{
        menuItemType="separator"
    },
    # Add the 'Terms & Conditions' link:
    @{
        name="Terms & Conditions";
        menuItemType="link";
        url="https://my.company.com/tsandcs/"
    }
)
### End of File ###