using System;
using System.Collections.Generic;
using System.Threading.Tasks;
using CitizenFX.Core;
using MenuAPI;
using static CitizenFX.Core.Native.API;

namespace RacesMenuApi
{
    public class Client : BaseScript
    {
        private readonly MenuController menuController;
        private readonly Menu mainMenu;
        private readonly Menu editInfoMenu;
        private readonly Menu propPlacerMenu;
        private readonly Menu raceSelectMenu;

        private readonly MenuItem editInfoButton;
        private readonly MenuItem addStartButton;
        private readonly MenuItem addCheckpointButton;
        private readonly MenuItem addTransformCheckpointButton;
        private readonly MenuItem removeStartButton;
        private readonly MenuItem removeCheckpointButton;
        private readonly MenuItem removeAllCheckpointsButton;
        private readonly MenuItem importRockstarButton;
        private readonly MenuItem statusButton;
        private readonly MenuItem saveButton;
        private readonly MenuItem cancelButton;
        private readonly MenuItem propPlacerButton;

        private readonly MenuItem raceIdButton;
        private readonly MenuItem raceNameButton;
        private readonly MenuItem vehicleButton;
        private readonly MenuItem propSpawnButton;
        private readonly MenuItem propDeleteButton;
        private readonly MenuItem propDuplicateButton;
        private readonly MenuItem propChangeModelButton;
        private readonly MenuItem propCycleButton;
        private readonly MenuItem propUndoButton;
        private readonly MenuItem propRedoButton;

        private bool builderActive;
        private bool raceSelectActive;
        private bool suppressCloseCancel;
        private bool propPlacerEnabled;
        private string raceId = "";
        private string raceName = "";
        private string vehicle = "";
        private int startCount;
        private int checkpointCount;

        public Client()
        {
            menuController = new MenuController();
#if FIVEM
            MenuController.MenuAlignment = MenuController.MenuAlignmentOption.Left;
#endif
            MenuController.PreventExitingMenu = false;
            MenuController.DisableBackButton = false;
            MenuController.DontOpenAnyMenu = true;

            mainMenu = new Menu("Race Builder", "No race loaded");
            MenuController.AddMenu(mainMenu);
            MenuController.MainMenu = mainMenu;

            raceSelectMenu = new Menu("Race Select", "Choose a race to start");
            MenuController.AddMenu(raceSelectMenu);

            editInfoMenu = new Menu("Edit Race", "Change race metadata");
            MenuController.AddSubmenu(mainMenu, editInfoMenu);

            propPlacerMenu = new Menu("Prop Placer", "Noclip + placement tools");
            MenuController.AddSubmenu(mainMenu, propPlacerMenu);

            editInfoButton = new MenuItem("Edit Race Info", "Change the race id, name, or vehicle")
            {
                LeftIcon = MenuItem.Icon.INFO,
                Label = "Open"
            };
            mainMenu.AddMenuItem(editInfoButton);
            MenuController.BindMenuItem(mainMenu, editInfoMenu, editInfoButton);

            propPlacerButton = new MenuItem("Prop Placer", "Enter noclip placement mode and edit props")
            {
                LeftIcon = MenuItem.Icon.BRIEFCASE,
                Label = "Open"
            };
            mainMenu.AddMenuItem(propPlacerButton);
            MenuController.BindMenuItem(mainMenu, propPlacerMenu, propPlacerButton);

            addStartButton = new MenuItem("Add Start Point", "Capture your current position as a grid start")
            {
                LeftIcon = MenuItem.Icon.RACE_FLAG_CAR
            };
            mainMenu.AddMenuItem(addStartButton);

            addCheckpointButton = new MenuItem("Add Checkpoint", "Capture your current position as a checkpoint")
            {
                LeftIcon = MenuItem.Icon.RACE_FLAG
            };
            mainMenu.AddMenuItem(addCheckpointButton);

            addTransformCheckpointButton = new MenuItem("Add Transform Checkpoint", "Capture your current position as a transform checkpoint")
            {
                LeftIcon = MenuItem.Icon.RACE_FLAG
            };
            mainMenu.AddMenuItem(addTransformCheckpointButton);

            removeStartButton = new MenuItem("Remove Start Spawn", "Remove the nearest start point under your player")
            {
                LeftIcon = MenuItem.Icon.WARNING
            };
            mainMenu.AddMenuItem(removeStartButton);

            removeCheckpointButton = new MenuItem("Remove Checkpoint", "Remove the nearest checkpoint under your player")
            {
                LeftIcon = MenuItem.Icon.WARNING
            };
            mainMenu.AddMenuItem(removeCheckpointButton);

            removeAllCheckpointsButton = new MenuItem("Remove All Checkpoints", "Delete all checkpoints from this race")
            {
                LeftIcon = MenuItem.Icon.WARNING
            };
            mainMenu.AddMenuItem(removeAllCheckpointsButton);

            importRockstarButton = new MenuItem("Import Rockstar Race", "Paste a Rockstar Social Club job URL to import a UGC race")
            {
                LeftIcon = MenuItem.Icon.STAR
            };
            mainMenu.AddMenuItem(importRockstarButton);

            statusButton = new MenuItem("Builder Status", "Shows the current race metadata")
            {
                LeftIcon = MenuItem.Icon.INFO,
                Enabled = false
            };
            mainMenu.AddMenuItem(statusButton);

            saveButton = new MenuItem("Save Race", "Write the current builder state back to races.json")
            {
                LeftIcon = MenuItem.Icon.TICK
            };
            mainMenu.AddMenuItem(saveButton);

            cancelButton = new MenuItem("Cancel Builder", "Discard the current builder session")
            {
                LeftIcon = MenuItem.Icon.LOCK_ARENA
            };
            mainMenu.AddMenuItem(cancelButton);

            raceIdButton = new MenuItem("Race ID", "Rename the race identifier")
            {
                LeftIcon = MenuItem.Icon.CAR
            };
            editInfoMenu.AddMenuItem(raceIdButton);

            raceNameButton = new MenuItem("Race Name", "Rename the visible race name")
            {
                LeftIcon = MenuItem.Icon.STAR
            };
            editInfoMenu.AddMenuItem(raceNameButton);

            vehicleButton = new MenuItem("Vehicle", "Change the race vehicle spawn code")
            {
                LeftIcon = MenuItem.Icon.CAR
            };
            editInfoMenu.AddMenuItem(vehicleButton);

            propSpawnButton = new MenuItem("Spawn Prop", "Enter model name to spawn in front of camera")
            {
                LeftIcon = MenuItem.Icon.STAR
            };
            propPlacerMenu.AddMenuItem(propSpawnButton);

            propDeleteButton = new MenuItem("Delete Selected Prop", "Delete currently selected prop")
            {
                LeftIcon = MenuItem.Icon.WARNING
            };
            propPlacerMenu.AddMenuItem(propDeleteButton);

            propDuplicateButton = new MenuItem("Duplicate Prop", "Duplicate selected prop in front of camera")
            {
                LeftIcon = MenuItem.Icon.STAR
            };
            propPlacerMenu.AddMenuItem(propDuplicateButton);

            propChangeModelButton = new MenuItem("Change Model", "Change the model of selected prop")
            {
                LeftIcon = MenuItem.Icon.STAR
            };
            propPlacerMenu.AddMenuItem(propChangeModelButton);

            propCycleButton = new MenuItem("Cycle Props", "Cycle through placed props to select")
            {
                LeftIcon = MenuItem.Icon.STAR
            };
            propPlacerMenu.AddMenuItem(propCycleButton);

            propUndoButton = new MenuItem("Undo", "Undo last prop placement/edit action")
            {
                LeftIcon = MenuItem.Icon.TICK
            };
            propPlacerMenu.AddMenuItem(propUndoButton);

            propRedoButton = new MenuItem("Redo", "Redo last undone prop action")
            {
                LeftIcon = MenuItem.Icon.TICK
            };
            propPlacerMenu.AddMenuItem(propRedoButton);

            mainMenu.OnItemSelect += HandleMainMenuSelect;
            mainMenu.OnMenuClose += HandleMainMenuClose;
            editInfoMenu.OnItemSelect += HandleEditMenuSelect;
            propPlacerMenu.OnItemSelect += HandlePropPlacerMenuSelect;
            propPlacerMenu.OnMenuClose += HandlePropPlacerMenuClose;
            raceSelectMenu.OnItemSelect += HandleRaceSelectMenuSelect;
            raceSelectMenu.OnMenuClose += HandleRaceSelectMenuClose;

            EventHandlers["racebuilder:setActive"] += new Action<bool>(OnBuilderActiveChanged);
            EventHandlers["racebuilder:updateMeta"] += new Action<string, string, string, int, int, bool>(OnBuilderMetaUpdated);
            EventHandlers["racebuilder:propplacerState"] += new Action<bool>(OnPropPlacerStateChanged);
            EventHandlers["race:menuClear"] += new Action(OnRaceMenuClear);
            EventHandlers["race:menuAddEntry"] += new Action<string, string, bool>(OnRaceMenuAddEntry);
            EventHandlers["race:menuOpen"] += new Action(OnRaceMenuOpen);
            EventHandlers["onResourceStop"] += new Action<string>(OnResourceStop);

            RefreshMenuState();
        }

        private async void HandleMainMenuSelect(Menu menu, MenuItem item, int itemIndex)
        {
            if (item == addStartButton)
            {
                TriggerEvent("racebuilder:captureStart");
                return;
            }

            if (item == addCheckpointButton)
            {
                TriggerEvent("racebuilder:setCheckpointType", "normal");
                TriggerEvent("racebuilder:captureCheckpoint");
                return;
            }

            if (item == addTransformCheckpointButton)
            {
                TriggerEvent("racebuilder:setCheckpointType", "transform");
                TriggerEvent("racebuilder:captureCheckpoint");
                return;
            }

            if (item == removeStartButton)
            {
                TriggerEvent("racebuilder:captureRemoveStart");
                return;
            }

            if (item == removeCheckpointButton)
            {
                TriggerEvent("racebuilder:captureRemoveCheckpoint");
                return;
            }

            if (item == removeAllCheckpointsButton)
            {
                TriggerEvent("racebuilder:removeAllCheckpoints");
                return;
            }

            if (item == importRockstarButton)
            {
                TriggerEvent("racebuilder:importRockstar");
                return;
            }

            if (item == saveButton)
            {
                TriggerEvent("racebuilder:propplacer:syncToServer");
                await BaseScript.Delay(100);
                TriggerServerEvent("racebuilder:keySave");
                return;
            }

            if (item == cancelButton)
            {
                TriggerServerEvent("racebuilder:keyCancel");
                return;
            }

            if (item == statusButton)
            {
                TriggerServerEvent("racebuilder:keyStatus");
                return;
            }

            if (item == propPlacerButton && !propPlacerEnabled)
            {
                TriggerEvent("racebuilder:propplacer:toggle");
            }
        }

        private async void HandleEditMenuSelect(Menu menu, MenuItem item, int itemIndex)
        {
            if (item == raceIdButton)
            {
                await PromptAndSaveInfoAsync("Race ID", raceId, 40, value => raceId = value);
                return;
            }

            if (item == raceNameButton)
            {
                await PromptAndSaveInfoAsync("Race Name", raceName, 64, value => raceName = value);
                return;
            }

            if (item == vehicleButton)
            {
                await PromptAndSaveInfoAsync("Vehicle Spawn Code", vehicle, 32, value => vehicle = value);
            }
        }

        private async Task PromptAndSaveInfoAsync(string title, string defaultValue, int maxLength, Action<string> onSuccess)
        {
            string result = await PromptTextInput(title, defaultValue, maxLength);
            if (string.IsNullOrWhiteSpace(result))
            {
                return;
            }

            onSuccess(result.Trim());
            TriggerServerEvent("racebuilder:updateInfo", raceId, raceName, vehicle);
        }

        private async void HandlePropPlacerMenuSelect(Menu menu, MenuItem item, int itemIndex)
        {
            if (item == propSpawnButton)
            {
                string modelName = await PromptTextInput("Prop model", "prop_barrier_work06a", 64);
                if (!string.IsNullOrWhiteSpace(modelName))
                {
                    TriggerEvent("racebuilder:propplacer:spawn", modelName.Trim());
                }
                return;
            }

            if (item == propDeleteButton)
            {
                TriggerEvent("racebuilder:propplacer:deleteSelected");
                return;
            }

            if (item == propDuplicateButton)
            {
                TriggerEvent("racebuilder:propplacer:duplicate");
                return;
            }

            if (item == propChangeModelButton)
            {
                string modelName = await PromptTextInput("New prop model", "prop_barrier_work06a", 64);
                if (!string.IsNullOrWhiteSpace(modelName))
                {
                    TriggerEvent("racebuilder:propplacer:changeModel", modelName.Trim());
                }
                return;
            }

            if (item == propCycleButton)
            {
                TriggerEvent("racebuilder:propplacer:cycleProp");
                return;
            }

            if (item == propUndoButton)
            {
                TriggerEvent("racebuilder:propplacer:undo");
                return;
            }

            if (item == propRedoButton)
            {
                TriggerEvent("racebuilder:propplacer:redo");
            }
        }

        private void HandlePropPlacerMenuClose(Menu menu)
        {
            if (propPlacerEnabled)
            {
                TriggerEvent("racebuilder:propplacer:forceOff");
            }
        }

        // Removed HandleScaleHoverTick method as it is no longer needed

        private async Task<string> PromptTextInput(string title, string defaultText, int maxLength)
        {
            AddTextEntry("RACE_BUILDER_MENU_INPUT", title);
            DisplayOnscreenKeyboard(1, "RACE_BUILDER_MENU_INPUT", string.Empty, defaultText ?? string.Empty, string.Empty, string.Empty, string.Empty, maxLength);

            while (UpdateOnscreenKeyboard() == 0)
            {
                await Delay(0);
            }

            if (UpdateOnscreenKeyboard() == 1)
            {
                return GetOnscreenKeyboardResult();
            }

            return null;
        }

        private async void HandleMainMenuClose(Menu menu)
        {
            if (suppressCloseCancel)
            {
                return;
            }

            await Delay(0);

            if (MenuController.IsAnyMenuOpen())
            {
                return;
            }

            if (builderActive)
            {
                TriggerServerEvent("racebuilder:keyCancel");
            }
        }

        private void HandleRaceSelectMenuSelect(Menu menu, MenuItem item, int itemIndex)
        {
            string selectedRaceId = item?.ItemData as string;
            if (string.IsNullOrWhiteSpace(selectedRaceId))
            {
                return;
            }

            TriggerServerEvent("race:selectAndStart", selectedRaceId);
            raceSelectActive = false;
            UpdateMenuAvailability();
            raceSelectMenu.CloseMenu();
        }

        private void HandleRaceSelectMenuClose(Menu menu)
        {
            raceSelectActive = false;
            UpdateMenuAvailability();
        }

        private void OnBuilderActiveChanged(bool isActive)
        {
            builderActive = isActive;
            UpdateMenuAvailability();

            if (builderActive)
            {
                if (raceSelectMenu.Visible)
                {
                    raceSelectActive = false;
                    raceSelectMenu.CloseMenu();
                }
                mainMenu.OpenMenu();
            }
            else if (mainMenu.Visible)
            {
                suppressCloseCancel = true;
                mainMenu.CloseMenu();
                suppressCloseCancel = false;
                TriggerEvent("racebuilder:propplacer:forceOff");
            }
        }

        private void OnBuilderMetaUpdated(string id, string name, string spawnVehicle, int starts, int checkpoints, bool isActive)
        {
            builderActive = isActive;
            raceId = id ?? string.Empty;
            raceName = name ?? string.Empty;
            vehicle = spawnVehicle ?? string.Empty;
            startCount = starts;
            checkpointCount = checkpoints;

            UpdateMenuAvailability();
            RefreshMenuState();

            if (builderActive && !mainMenu.Visible)
            {
                mainMenu.OpenMenu();
            }
            else if (!builderActive && mainMenu.Visible)
            {
                suppressCloseCancel = true;
                mainMenu.CloseMenu();
                suppressCloseCancel = false;
            }
        }

        private void OnRaceMenuClear()
        {
            raceSelectMenu.ClearMenuItems();
            raceSelectMenu.MenuSubtitle = "Choose a race to start";
        }

        private void OnRaceMenuAddEntry(string id, string name, bool hasGrid)
        {
            string raceIdValue = id ?? string.Empty;
            string raceNameValue = string.IsNullOrWhiteSpace(name) ? raceIdValue : name;
            string label = hasGrid ? "Start" : "No Grid";

            var item = new MenuItem(raceNameValue, "Race ID: " + raceIdValue)
            {
                Label = label,
                LeftIcon = hasGrid ? MenuItem.Icon.RACE_FLAG : MenuItem.Icon.WARNING,
                Enabled = hasGrid,
                ItemData = raceIdValue
            };
            raceSelectMenu.AddMenuItem(item);
        }

        private void OnRaceMenuOpen()
        {
            if (builderActive)
            {
                return;
            }

            if (raceSelectMenu.GetMenuItems().Count < 1)
            {
                return;
            }

            raceSelectActive = true;
            UpdateMenuAvailability();
            raceSelectMenu.RefreshIndex();
            raceSelectMenu.OpenMenu();
        }

        private void UpdateMenuAvailability()
        {
            MenuController.DontOpenAnyMenu = !(builderActive || raceSelectActive);
        }

        private void RefreshMenuState()
        {
            string safeRaceId = string.IsNullOrWhiteSpace(raceId) ? "<unset>" : raceId;
            string safeRaceName = string.IsNullOrWhiteSpace(raceName) ? "<unset>" : raceName;
            string safeVehicle = string.IsNullOrWhiteSpace(vehicle) ? "<unset>" : vehicle;

            mainMenu.MenuSubtitle = $"ID: {safeRaceId} | Starts: {startCount} | Checkpoints: {checkpointCount}";
            editInfoButton.Label = "Open";
            addStartButton.Label = startCount.ToString();
            addCheckpointButton.Label = "Normal";
            addCheckpointButton.Description = "Capture your current position as a normal checkpoint.";
            addTransformCheckpointButton.Label = "Transform";
            addTransformCheckpointButton.Description = "Capture your current position as a transform checkpoint.";
            removeStartButton.Label = startCount.ToString();
            removeCheckpointButton.Label = checkpointCount.ToString();
            saveButton.Label = "Save";
            cancelButton.Label = "Cancel";
            propPlacerButton.Label = "Open";

            statusButton.Text = "Current Race";
            statusButton.Label = safeRaceId;
            statusButton.Description = $"Name: {safeRaceName}\nVehicle: {safeVehicle}\nStart spots: {startCount}\nCheckpoints: {checkpointCount}";

            raceIdButton.Label = safeRaceId;
            raceNameButton.Label = safeRaceName;
            vehicleButton.Label = safeVehicle;

            propPlacerMenu.MenuSubtitle = "Numpad 4/6 = X, 8/2 = active axis, 5 toggles Y/Z";
            propDeleteButton.Label = "Delete";
            propDuplicateButton.Label = "Duplicate";
            propUndoButton.Label = "Undo";
            propRedoButton.Label = "Redo";
        }

        private void OnPropPlacerStateChanged(bool isActive)
        {
            propPlacerEnabled = isActive;
        }

        private void OnResourceStop(string resourceName)
        {
            if (resourceName != GetCurrentResourceName())
            {
                return;
            }

            MenuController.CloseAllMenus();
            MenuController.DontOpenAnyMenu = false;
        }
    }
}
