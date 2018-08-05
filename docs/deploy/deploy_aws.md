# Deploying an Aqueduct Application on Amazon Web Services (AWS)

For other deployment options, see [Deploying Aqueduct Applications](index.md).

### Purpose

To run a production Aqueduct application on Amazon Web Services. Make sure to also read [Testing Aqueduct Applications](../testing/index.md).

### Prerequisites

1. [Dart has been installed on your local machine.](https://www.dartlang.org/install)
2. [An AWS Account](https://aws.amazon.com)
3. [A GitHub Account*](https://github.com)
4. [`git` has been installed](https://git-scm.com/downloads) on your local machine.
5. [Aqueduct has been activated on your local machine.](../index.md#getting_started)

\* GitHub will be used for transferring code to the remote machine. You could use `ftp`, `scp`, `rsync`, another Git provider, another VCS system, AWS's CodeDeploy, etc.

Estimated Time: <15 minutes.

### Overview

1. Setting up the Aqueduct application and GitHub
2. Setting up an EC2 Instance
3. Setting up a Database
3. Configuring application values
5. Running the Aqueduct application


### Step 1: Setting up the Aqueduct Application

Set up a new GitHub repository with the name of your application. The purpose of GitHub here is to transfer the application code to the AWS instance. There are other ways of accomplishing this, so as long as you can get the source code to the machine, you're in good shape.

If you have not yet, create a new Aqueduct application on your local machine, go into that directory, and initialize it as a git repository:

```bash
aqueduct create app_name
cd app_name
git init
```

Then, setup your local git repository with your remote git repository for the application by executing one of the following commands in the project's directory:

```bash
# If your machine is set up to use git over SSH ...
git remote add origin git@github.com:organization/app_name.git

# If your machine is set up to use git over HTTPS
git remote add origin https://github.com/organization/app_name.git

# If you are unsure or haven't set up GitHub before,
# see https://help.github.com/articles/set-up-git/
```

Then, grab the repository contents:

```bash
git pull
```

Keep the GitHub web interface open, as you'll have to come back to it one more time.

### Step 2: Setting up an EC2 Instance

In the AWS EC2 control panel, create a new Ubuntu instance. Make sure your VPC has DNS resolution (the default VPC configuration does). Choose or create a security group that allows both HTTP and SSH access for this instance. The rest of the default configuration values are fine.

Launch that instance. When prompted, make sure you either create a new key pair or have access to an existing key pair.

After creating the EC2 instance, select it in the AWS console and click 'Connect' for instructions on how to SSH into the instance.  

It's useful to add the `ssh` command that connects to this instance as an alias in your shell and the key file into more permanent storage. The command is something like `ssh -i key.pem ubuntu@host`. Move the key file `key.pem` into `~/.ssh` (it may be named differently):

```bash
cp key.pem ~/.ssh/key.pem
```

Then add the following line to the file `~/.bash_profile` and then reload your profle:

```
alias app_name="ssh -i ~/.ssh/key.pem ubuntu@host"
source ~/.bash_profile
```

Next, SSH into the EC2 instance by executing the alias locally:

```bash
app_name
```

Once the shell for the instance is opened, install Dart (these instructions are located at https://www.dartlang.org/install/linux):

```bash
sudo apt-get update
sudo apt-get install apt-transport-https
sudo sh -c 'curl https://dl-ssl.google.com/linux/linux_signing_key.pub | apt-key add -'
sudo sh -c 'curl https://storage.googleapis.com/download.dartlang.org/linux/debian/dart_stable.list > /etc/apt/sources.list.d/dart_stable.list'
sudo apt-get update
sudo apt-get install dart
```

When these steps are completed correctly, the following command will yield `/usr/bin/dart`:

```bash
which dart
```

Add the Dart executable directories to your path by adding the following line to the end of the file `~/.profile`:

```
export PATH=$PATH:"/usr/lib/dart/bin":"~/.pub-cache/bin"
```

Then reload the profile:

```bash
source ~/.profile
```

Now, we'll give this instance permission to clone the application repository from GitHub. In the instance's shell, install `git` and create a new SSH key:

```bash
sudo apt-get install git
ssh-keygen -t rsa -b 4096 -C 'youremail'
```

This command will prompt you three times (for a file name, password and password confirm). Simply hit the Enter key each time.
Then, add the following to the file `/etc/ssh/ssh_config` (requires `sudo`):

```
Host github.com
    Hostname github.com
    IdentityFile ~/.ssh/id_rsa
    User git
```

Print out the contents of the public key and copy them:

```bash
cat ~/.ssh/id_rsa.pub
```

The contents will start with the phrase `ssh-rsa` and end with your email, and you must copy all of it.

In the GitHub repository web interface, select the `Settings` tab then select `Deploy keys`. Click `Add deploy key`. Enter "AWS" for the title and paste the contents of the public key into the `Key` area. Then click `Add key`.

To ensure this all works, clone the repository onto the AWS instance:

```bash
git clone git@github.com:organization/app_name.git
```

At this point, the repository should mostly be empty, but as long as it clones correctly you're in good shape.

### Step 3: Setting up a Database

In the AWS control panel, select the RDS service. Choose the `Instances` item from the left hand panel and select `Launch DB Instance`. Choose PostgreSQL and configure the database details. Make sure to store the username and password as you'll need them shortly.

In the `Configure Advanced Settings`, make sure the database is Publicly Accessible. Set `Database Name` to the name of your application, this will make it easy to remember.

Add a new Inbound entry to the security group for the database. The type must be `PostgreSQL` (which automatically configures the protocol to `TCP` and the port range to `5432`). Choose a custom Source and enter the name of the security group that the EC2 instance is in. (You can start by typing "sg-", and it give you a drop-down list so that you can select the appropriate one.)

Then, launch the database.

Once the database has finished launching, we must upload the application's schema. From the project directory on your local machine, run the following:

```bash
aqueduct db generate
```

Next, run the newly generated migration file on the database, substituting the values in the `--connect` option with values from the recently configured database:

```bash
aqueduct db upgrade --connect postgres://username:password@host:5432/app_name
```


### Step 4: Configuring the Application

Configuring an Aqueduct application on AWS means having a configuration file that lives on the instance, but is not checked into source control. There are tools for managing configurations across instances, but those are up to you.

In the project directory on your local machine, add all of the project files to the git repository:

```bash
git add .
git commit -am "Initial commit"
git push -u origin master
```

On the EC2 instance, grab these files from the repository (this assumes you ran `git clone` earlier).

```bash
cd app_name
git pull
```

Create a new configuration file just for this instance by cloning the configuration template file that is checked into the repository:

```bash
cp config.yaml.src config.yaml
```

Modify `config.yaml` by replacing the database credentials with the credentials of the RDS database and change `logging:type` to `file`:

```
database:
 username: username
 password: password
 host: host
 port: 5432
 databaseName: app_name
logging:
 type: file
 filename: api.log
```

### Step 5: Running the Application

Then, activate the Aqueduct package:

```bash
pub global activate aqueduct
```

Fetch the application's dependencies:

```bash
pub get
```

Now, run the application in `--detached` mode:

```bash
aqueduct serve --detached
```

By default, an Aqueduct application will listen on port 8888. HTTP requests will come in on port 80. You can't bind to port 80 without using sudo. Instead, reroute HTTP requests on port 80 to port 8888 by entering the following on the EC2 instance:

```bash
sudo iptables -t nat -A PREROUTING -p tcp --dport 80 -j REDIRECT --to 8888
sudo iptables-save
```

Then - either locally or remotely - add a new OAuth 2.0 client:

```bash
  aqueduct auth add-client --id com.app.standard --secret secret --connect postgres://user:password@deploy-aws.hexthing.us-east-1.rds.amazonaws.com:5432/deploy_aws
```

Your Aqueduct application is now up and running.
