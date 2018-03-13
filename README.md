# Azure Addendum Management Pack
This management pack suite extends the Azure Monitoring Management Pack integrating:

- Log Analytics
- Azure Backup
- Azure Backup Server
- Azure Automation
- Azure Storage
- Azure Monitoring

Version [1705](https://github.com/QuaeNocentDocent/OMS-ManagementPack/releases/tag/1705) is the latest with support of ASM workloads, starting from version [1712](https://github.com/QuaeNocentDocent/OMS-ManagementPack/releases/tag/1712) only ARM worklaods are supported. Version 1712 introduced significant changes and thus is not backward compatible. 
While I know this is far from optimum, the breaking changes were needed to:

- remove the dependency to the Monitor Azure Wizard in Operations Manager
- remove all the dependency to ASM artifacts

# How to activate the management packs

The management packs depends from the official Microsoft Azure Management Pack, the dependecy is primarily needed to allow a clean registration of the subscription to be monitored. 
To activate the management packs you must first import the Microsoft Azure MP and register all the subscriptions to be monitored and that's all. 
It is not necessary to run the Microsoft Azure Monitoring wiard in the authoring pane (this is true starting with version 1712).

Please consider these management packs are under constant review and at the moment upgrade compatibility cannot be guaranteed for future releases. Documentation is at a bare minimum, KB articles maybe missing.
Any contribution is warmly welcomed.
